import Foundation

/// Cardiovascular load ("Effort", 0–21).
///
/// Method (NOOP `StrainScorer`, the WHOOP-like one): every second of heart rate is weighted by
/// its heart-rate-reserve zone (Karvonen %HRR; weights 1…5 at 50 / 60 / 70 / 80 / 90 %, the
/// Edwards summation read on %HRR), summed in zone-minutes, then log-compressed:
///
///     effort = 21 · ln(load + 1) / ln(D),   D = 7201
///
/// `D` puts 24 h in the top zone (5 × 1440) exactly at 21, so each extra point costs
/// exponentially more — which is what makes a day's total barely move after a big session.
///
/// Below zone 1 the weight does not drop to zero: it decays exponentially
/// (`e^(−11,5·(0,5 − x))`), so being up and about adds a little all day long, as on WHOOP. The
/// decay rate is set on a real WHOOP day (the wearer's own): a 2 h 26 ride at 12,6 and a 40-min
/// hike at 4,1 made a 12,8 day by 16:19 — the hike's load is that of ~31 % HRR, and the ~5 other
/// waking hours fit in what is left.
///
/// `D` can be re-fitted on the wearer's own WHOOP workouts (see `Calibration`).
enum Strain {
    static let maxStrain = 21.0
    static let defaultDenominator = 7201.0
    /// Decay rate of the weight below zone 1 (per unit of heart-rate-reserve fraction).
    static let subZoneDecay = 11.5
    static let zoneCuts: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90]

    static func hrr(_ hr: Double, rest: Double, max: Double) -> Double {
        guard max > rest else { return 0 }
        return Stats.clamp((hr - rest) / (max - rest), 0, 1)
    }

    /// Load weight (per minute) of a heart-rate-reserve fraction.
    static func weight(_ x: Double) -> Double {
        if x >= 0.90 { return 5 }
        if x >= 0.80 { return 4 }
        if x >= 0.70 { return 3 }
        if x >= 0.60 { return 2 }
        if x >= 0.50 { return 1 }
        return exp(-subZoneDecay * (0.50 - max(0, x)))
    }

    /// Effort for a load in weighted zone-minutes.
    static func fromLoad(_ load: Double, denominator: Double = defaultDenominator) -> Double {
        guard load.isFinite, load > 0, denominator > 1 else { return 0 }
        return Stats.clamp(maxStrain * log(load + 1) / log(denominator), 0, maxStrain)
    }

    /// Inverse of `fromLoad`: the load that yields a given effort.
    static func load(forStrain strain: Double, denominator: Double = defaultDenominator) -> Double {
        let s = Stats.clamp(strain, 0, maxStrain)
        return exp(s / maxStrain * log(denominator)) - 1
    }

    /// Accumulates heart rate into load.
    struct Accumulator {
        let rest: Double
        let maxHR: Double
        let denominator: Double
        private(set) var load = 0.0
        private(set) var minutes = 0.0

        init(rest: Double, maxHR: Double, denominator: Double = Strain.defaultDenominator) {
            self.rest = rest
            self.maxHR = maxHR
            self.denominator = denominator
        }

        /// - Parameter weight: minutes this heart-rate value covers.
        mutating func add(_ hr: Double, weight: Double = 1) {
            guard hr.isFinite, hr > 0, weight > 0 else { return }
            load += Strain.weight(Strain.hrr(hr, rest: rest, max: maxHR)) * weight
            minutes += weight
        }

        var strain: Double { Strain.fromLoad(load, denominator: denominator) }
    }

    /// WHOOP heart-rate zones on heart-rate reserve: 0 (< 50 %), 1 (50–60), 2 (60–70),
    /// 3 (70–80), 4 (80–90), 5 (≥ 90).
    static func zone(_ hr: Double, rest: Double, maxHR: Double) -> Int {
        guard maxHR > rest, hr > 0 else { return 0 }
        let x = (hr - rest) / (maxHR - rest)
        var z = 0
        for c in zoneCuts where x >= c { z += 1 }
        return z
    }

    /// Heart rate at the lower edge of a zone (1…5).
    static func zoneFloor(_ zone: Int, rest: Double, maxHR: Double) -> Double {
        let i = Swift.max(1, Swift.min(5, zone)) - 1
        return rest + zoneCuts[i] * (maxHR - rest)
    }

    /// Keytel et al. 2005 energy expenditure from HR (kcal/min).
    static func keytelKcalPerMin(hr: Double, profile: UserProfile) -> Double {
        let w = profile.weightKg, a = Double(profile.age)
        let kj: Double
        if profile.sex == .male {
            kj = -55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a
        } else {
            kj = -20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a
        }
        return Swift.max(0, kj / 4.184)
    }

    /// Calories for one minute: BMR share, raised by Keytel during exertion.
    /// `activeScale` rescales the part above basal (personal WHOOP calibration; 1 = none).
    static func kcalForMinute(hr: Double?, asleep: Bool, rest: Double, maxHR: Double, profile: UserProfile,
                              activeScale: Double = 1) -> (total: Double, active: Double) {
        let basal = profile.bmr / 1440
        if asleep { return (basal * 0.95, 0) }
        guard let hr, hr > 0 else { return (basal * 1.1, 0) }
        let x = hrr(hr, rest: rest, max: maxHR)
        var k: Double
        if x >= 0.30 {
            k = Swift.max(basal * 1.1, keytelKcalPerMin(hr: hr, profile: profile))
        } else {
            // Light activity (standing, pottering): a small HR-proportional uplift.
            k = basal * (1.1 + 0.6 * x / 0.30)
        }
        let active = Swift.max(0, k - basal) * activeScale
        k = basal + active
        return (k, active)
    }

    /// The wearer's quiet waking level for a day: median per-minute %HRR over awake worn
    /// minutes; nil when too little wear or implausibly high. (Kept for the stress monitor.)
    static func dailyQuietHRR(minuteHR: [Double], rest: Double, maxHR: Double) -> Double? {
        guard minuteHR.count >= 180 else { return nil }
        let x = minuteHR.map { hrr($0, rest: rest, max: maxHR) }
        guard let q = Stats.median(x), q > 0, q <= 0.40 else { return nil }
        return q
    }
}

/// Automatic workout detection: sustained elevated heart rate outside sleep.
enum ActivityDetector {
    struct Bout { let start: Int; let end: Int }

    /// `hr` = per-minute HR (nil = no data), `minuteStart(i)` = unix of minute i.
    static func detect(hr: [Double?], start: Int, rest: Double, maxHR: Double, sleeping: (Int) -> Bool,
                       minMinutes: Int = 15) -> [Bout] {
        let thr = 0.35
        var active = [Bool](repeating: false, count: hr.count)
        for i in hr.indices {
            if let h = hr[i], !sleeping(i) { active[i] = Strain.hrr(h, rest: rest, max: maxHR) >= thr }
        }
        var out: [Bout] = []
        var i = 0
        while i < hr.count {
            guard active[i] else { i += 1; continue }
            var j = i, gap = 0, k = i + 1
            while k < hr.count {
                if active[k] { j = k; gap = 0 } else { gap += 1; if gap > 4 { break } }
                k += 1
            }
            let len = j - i + 1
            let activeMinutes = (i...j).filter { active[$0] }.count
            if len >= minMinutes && Double(activeMinutes) >= 0.7 * Double(len) {
                out.append(Bout(start: start + 60 * i, end: start + 60 * (j + 1)))
            }
            i = j + 1
        }
        return out
    }
}
