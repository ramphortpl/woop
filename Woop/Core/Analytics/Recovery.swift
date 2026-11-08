import Foundation

/// Personal baseline for one metric from previous nights.
struct Baseline: Equatable {
    let mean: Double
    let sigma: Double
    let n: Int

    /// Robust baseline from up to the last 30 values: winsorized mean, 1.253·MAD sigma
    /// (MAD→σ for a normal distribution), floored so a very steady history cannot turn a tiny
    /// change into an extreme z-score.
    static func from(_ values: [Double], minCount: Int, sigmaFloor: Double) -> Baseline? {
        let v = Array(values.suffix(30))
        guard v.count >= minCount, let m = Stats.winsorizedMean(v), let mad = Stats.meanAbsDev(v) else { return nil }
        return Baseline(mean: m, sigma: max(1.253 * mad, sigmaFloor), n: v.count)
    }

    func z(_ x: Double) -> Double { (x - mean) / sigma }
}

/// Recovery 0–100: HRV-dominant composite z-score against the wearer's own baselines,
/// squashed by a logistic so the population mean sits near 58 (NOOP RecoveryScorer weights:
/// HRV 0.55, RHR 0.20, sleep 0.15, respiration 0.05, skin temperature 0.05).
enum Recovery {
    static let wHRV = 0.55, wRHR = 0.20, wSleep = 0.15, wResp = 0.05, wTemp = 0.05
    static let logisticK = 1.6, logisticZ0 = -0.20
    /// Nights of HRV needed before the first score (WHOOP calibrates for a few days too).
    static let calibrationNights = 4

    struct Inputs {
        var hrv: Double
        var rhr: Double?
        var resp: Double?
        var sleepPerformance: Double? // 0–100
        var skinTempDev: Double?
    }

    struct Baselines {
        var hrv: Baseline?
        var rhr: Baseline?
        var resp: Baseline?
    }

    static func baselines(history: [DayMetrics]) -> Baselines {
        Baselines(
            hrv: Baseline.from(history.compactMap(\.hrv), minCount: calibrationNights - 1, sigmaFloor: 0),
            rhr: Baseline.from(history.compactMap(\.rhr), minCount: 3, sigmaFloor: 1.5),
            resp: Baseline.from(history.compactMap(\.respRate), minCount: 3, sigmaFloor: 0.4))
    }

    static func score(_ i: Inputs, _ b: Baselines) -> Double? {
        guard let hb = b.hrv else { return nil }
        let hrvSigma = max(hb.sigma, 0.08 * hb.mean)
        var terms: [(z: Double, w: Double)] = [((i.hrv - hb.mean) / hrvSigma, wHRV)]
        if let rhr = i.rhr, let rb = b.rhr { terms.append(((rb.mean - rhr) / rb.sigma, wRHR)) }
        if let r = i.resp, let bb = b.resp { terms.append(((bb.mean - r) / bb.sigma, wResp)) }
        if let sp = i.sleepPerformance { terms.append(((sp / 100 - 0.85) / 0.12, wSleep)) }
        if let d = i.skinTempDev { terms.append((-abs(d) / 1.0, wTemp)) }
        let wsum = terms.reduce(0) { $0 + $1.w }
        guard wsum > 0 else { return nil }
        let z = terms.reduce(0) { $0 + Stats.clamp($1.z, -4, 4) * $1.w } / wsum
        return Stats.clamp(100 / (1 + exp(-logisticK * (z - logisticZ0))), 1, 99)
    }

    enum Zone { case red, yellow, green }

    static func zone(_ score: Double) -> Zone {
        score < 34 ? .red : (score < 67 ? .yellow : .green)
    }
}

/// Sleep need, debt and consistency (WHOOP-style coaching layer).
enum SleepCoach {
    /// Extra need from yesterday's strain: up to 45 min at 21.
    static func strainBonusSec(_ strain: Double?) -> Double {
        (Stats.clamp(strain ?? 0, 0, 21) / 21) * 45 * 60
    }

    /// Debt carried into a night: weighted shortfall of the three previous nights, capped at 3 h.
    static func debtSec(previousNights: [(need: Double, slept: Double)]) -> Double {
        let weights = [0.6, 0.25, 0.15]
        var debt = 0.0
        for (k, n) in previousNights.prefix(3).enumerated() {
            debt += weights[k] * max(0, n.need - n.slept)
        }
        return min(debt, 3 * 3600)
    }

    static func needSec(baselineHours: Double, priorStrain: Double?, debtSec: Double, napSec: Double) -> Double {
        Stats.clamp(baselineHours * 3600 + strainBonusSec(priorStrain) + debtSec - napSec, 6 * 3600, 12 * 3600)
    }

    static func performance(asleepSec: Int, needSec: Double) -> Double? {
        guard needSec > 0 else { return nil }
        return Stats.clamp(Double(asleepSec) / needSec * 100, 0, 100)
    }

    /// Mean intersection-over-union of consecutive nights' sleep windows mapped onto a
    /// 24 h clock (last 4 nights). 100 % = identical bed and wake times.
    static func consistency(_ nights: [SleepSession]) -> Double? {
        let ns = Array(nights.suffix(4))
        guard ns.count >= 2 else { return nil }
        func minutes(_ s: SleepSession) -> Set<Int> {
            let a = DayKey.minuteOfDay(unix: s.start)
            let len = max(1, s.inBedSec / 60)
            return Set((0..<len).map { (a + $0) % 1440 })
        }
        var scores: [Double] = []
        for i in 1..<ns.count {
            let a = minutes(ns[i - 1]), b = minutes(ns[i])
            let u = a.union(b).count
            if u > 0 { scores.append(Double(a.intersection(b).count) / Double(u)) }
        }
        return Stats.mean(scores).map { $0 * 100 }
    }

    /// Bedtime that delivers `needSec` of sleep at the wearer's usual efficiency before `wake`.
    static func recommendedBedtime(wake: Date, needSec: Double, efficiency: Double) -> Date {
        let eff = Stats.clamp(efficiency, 0.75, 0.99)
        return wake.addingTimeInterval(-needSec / eff)
    }
}

/// VO₂max estimate from the heart-rate ratio method (Uth, Sørensen, Overgaard & Pedersen 2004).
enum Fitness {
    static func vo2max(maxHR: Double, restingHR: Double) -> Double? {
        guard restingHR > 30, maxHR > restingHR else { return nil }
        return Stats.clamp(15.3 * maxHR / restingHR, 15, 90)
    }
}

/// Strain Coach target for the day, from the morning recovery (WHOOP-style bands).
enum StrainTarget {
    static func forRecovery(_ r: Double?) -> ClosedRange<Double>? {
        guard let r else { return nil }
        switch r {
        case ..<34: return 4...9
        case ..<67: return 9...13.5
        default: return 13.5...18
        }
    }

    /// One optimal value inside the band, placed by where the recovery sits in its zone
    /// (e.g. 45 % → 10,5): the "Objectif d'effort" of an activity.
    static func optimal(for r: Double?) -> Double? {
        guard let r, let band = forRecovery(r) else { return nil }
        let (lo, hi): (Double, Double)
        switch r {
        case ..<34: (lo, hi) = (0, 34)
        case ..<67: (lo, hi) = (34, 67)
        default: (lo, hi) = (67, 100)
        }
        let t = Stats.clamp((r - lo) / (hi - lo), 0, 1)
        return ((band.lowerBound + t * (band.upperBound - band.lowerBound)) * 10).rounded() / 10
    }
}
