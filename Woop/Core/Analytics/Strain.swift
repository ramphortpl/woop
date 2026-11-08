import Foundation

/// Cardiovascular load ("Effort", 0–21).
///
/// Method (published): Banister TRIMP on heart-rate reserve (Karvonen %HRR) with the
/// sex-specific exponential weighting (Banister 1991; Morton 1990), counted ABOVE the wearer's
/// own quiet-waking level so a day of sitting scores ~0, with exercise minutes (≥ 40 % HRR,
/// ACSM moderate floor) never offset by quiet time. The net load is log-mapped onto 0–21:
/// `21 · ln(1 + u·(C−1)) / ln(C)`, `u = min(1, net / 400)`, `C = 15` — calibrated so a 60-min walk
/// lands ~3, a 45-min moderate run ~9, a 90-min hard session ~16–17 (anchors documented by
/// OpenStrap analytics).
enum Strain {
    static let maximalNetTrimp = 400.0
    static let curvature = 15.0
    static let exerciseFloorHRR = 0.40
    static let maxQuietHRR = 0.40
    static let defaultQuietHRR = 0.20

    static func banisterY(_ x: Double, female: Bool) -> Double {
        female ? 0.86 * exp(1.67 * x) : 0.64 * exp(1.92 * x)
    }

    static func hrr(_ hr: Double, rest: Double, max: Double) -> Double {
        guard max > rest else { return 0 }
        return Stats.clamp((hr - rest) / (max - rest), 0, 1)
    }

    /// Inverse of `fromNetTrimp` (net load that yields a given strain), to add a live session's
    /// load to the day's strain.
    static func netTrimp(forStrain strain: Double) -> Double {
        let s = Stats.clamp(strain, 0, 21)
        let u = (pow(curvature, s / 21) - 1) / (curvature - 1)
        return u * maximalNetTrimp
    }

    static func fromNetTrimp(_ net: Double) -> Double {
        guard net.isFinite, net > 0 else { return 0 }
        let u = min(1, net / maximalNetTrimp)
        return Stats.clamp(21 * log(1 + u * (curvature - 1)) / log(curvature), 0, 21)
    }

    /// Accumulates per-minute HR into net TRIMP; `exercise` never decreases.
    struct Accumulator {
        let rest: Double
        let maxHR: Double
        let female: Bool
        let quietRate: Double
        var exercise = 0.0
        var living = 0.0
        var minutes = 0

        init(rest: Double, maxHR: Double, quietHRR: Double, female: Bool) {
            self.rest = rest
            self.maxHR = maxHR
            self.female = female
            let q = Stats.clamp(quietHRR, 0.01, Strain.maxQuietHRR)
            quietRate = q * Strain.banisterY(q, female: female)
        }

        mutating func add(_ hr: Double, weight: Double = 1) {
            guard hr.isFinite, hr > 0 else { return }
            let x = Strain.hrr(hr, rest: rest, max: maxHR)
            let e = (x * Strain.banisterY(x, female: female) - quietRate) * weight
            if x >= Strain.exerciseFloorHRR { exercise += e } else { living += e }
            minutes += 1
        }

        var net: Double { exercise + max(0, living) }
        var strain: Double { Strain.fromNetTrimp(net) }
    }

    /// WHOOP heart-rate zones by % of max HR: 0 (<50 %), 1 (50–60), 2 (60–70), 3 (70–80),
    /// 4 (80–90), 5 (≥ 90).
    static func zone(_ hr: Double, maxHR: Double) -> Int {
        guard maxHR > 0, hr > 0 else { return 0 }
        let p = hr / maxHR
        switch p {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
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
        return max(0, kj / 4.184)
    }

    /// Calories for one minute: BMR share, raised by Keytel during exertion.
    static func kcalForMinute(hr: Double?, asleep: Bool, rest: Double, maxHR: Double, profile: UserProfile) -> (total: Double, active: Double) {
        let basal = profile.bmr / 1440
        if asleep { return (basal * 0.95, 0) }
        guard let hr, hr > 0 else { return (basal * 1.1, 0) }
        let x = hrr(hr, rest: rest, max: maxHR)
        if x >= 0.30 {
            let k = max(basal * 1.1, keytelKcalPerMin(hr: hr, profile: profile))
            return (k, max(0, k - basal))
        }
        // Light activity (standing, pottering): a small HR-proportional uplift.
        let k = basal * (1.1 + 0.6 * x / 0.30)
        return (k, max(0, k - basal))
    }

    /// The wearer's quiet waking level for a day: median per-minute %HRR over awake worn
    /// minutes; nil when too little wear or implausibly high.
    static func dailyQuietHRR(minuteHR: [Double], rest: Double, maxHR: Double) -> Double? {
        guard minuteHR.count >= 180 else { return nil }
        let x = minuteHR.map { hrr($0, rest: rest, max: maxHR) }
        guard let q = Stats.median(x), q > 0, q <= maxQuietHRR else { return nil }
        return q
    }

    /// Observed max-HR estimate: 99.5th percentile of recent HR, never below Tanaka.
    static func estimateMaxHR(recentHR: [Double], profile: UserProfile) -> Double {
        if let o = profile.maxHROverride, o > 100 { return Double(o) }
        let tanaka = profile.tanakaMaxHR
        guard recentHR.count >= 600, let p = Stats.percentile(recentHR, 99.5) else { return tanaka }
        return max(tanaka, min(p, 220))
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
