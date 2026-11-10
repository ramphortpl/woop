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

/// Recovery 0–100.
///
/// Default: an HRV-led composite z-score against the wearer's own baselines, squashed by a
/// logistic so the population mean sits near 58 (NOOP `RecoveryScorer`: HRV 0.55, RHR 0.20,
/// sleep 0.15, respiration 0.05, skin temperature 0.05).
///
/// With a WHOOP export imported, the weights and the logistic are instead FITTED on the wearer's
/// own WHOOP nights (`Calibration.RecoveryModel`): NOOP's analysis of real WHOOP data found the
/// score follows sleep performance and the HRV / resting-HR pair much more than the default
/// weights assume, and that the mapping "should become a personal calibration".
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
        var lnHRV: Baseline?
        var rhr: Baseline?
        var resp: Baseline?
    }

    static func baselines(history: [DayMetrics]) -> Baselines {
        let hrv = history.compactMap(\.hrv).filter { $0 > 0 }
        return Baselines(
            hrv: Baseline.from(hrv, minCount: calibrationNights - 1, sigmaFloor: 0),
            lnHRV: Baseline.from(hrv.map { log($0) }, minCount: calibrationNights - 1, sigmaFloor: 0.06),
            rhr: Baseline.from(history.compactMap(\.rhr), minCount: 3, sigmaFloor: 1.5),
            resp: Baseline.from(history.compactMap(\.respRate), minCount: 3, sigmaFloor: 0.4))
    }

    /// The standardized drivers shared by the default score and the personal model.
    struct Features: Equatable {
        var zLnHRV: Double
        var zRHR: Double?      // positive = resting HR above baseline (worse)
        var zResp: Double?     // positive = breathing faster than baseline (worse)
        var sleep: Double?     // (performance − 85) / 12
    }

    static func features(_ i: Inputs, _ b: Baselines) -> Features? {
        guard let lb = b.lnHRV, i.hrv > 0 else { return nil }
        return Features(
            zLnHRV: Stats.clamp(lb.z(log(i.hrv)), -4, 4),
            zRHR: i.rhr.flatMap { r in b.rhr.map { Stats.clamp($0.z(r), -4, 4) } },
            zResp: i.resp.flatMap { r in b.resp.map { Stats.clamp($0.z(r), -4, 4) } },
            sleep: i.sleepPerformance.map { Stats.clamp(($0 - 85) / 12, -5, 1.5) })
    }

    static func score(_ i: Inputs, _ b: Baselines, model: Calibration.RecoveryModel? = nil) -> Double? {
        if let model, let f = features(i, b) {
            return Stats.clamp(model.predict(f), 1, 99)
        }
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

/// Sleep need, debt, performance and consistency (WHOOP's coaching layer).
enum SleepCoach {
    /// WHOOP's "Votre sommeil" score blends four parts: hours vs. need, consistency, efficiency
    /// and high sleep stress. The default weights reproduce a real WHOOP night
    /// (70 % / 54 % / 97 % / 0 % → 76 %); `Calibration` re-fits them on an imported export.
    struct PerformanceWeights: Codable, Equatable, Sendable {
        var hours = 0.55
        var consistency = 0.15
        var efficiency = 0.20
        var stress = 0.10
        var intercept = 0.0
    }

    /// Extra need from yesterday's strain: up to 45 min at 21.
    static func strainBonusSec(_ strain: Double?, model: Calibration.NeedModel? = nil) -> Double {
        let s = Stats.clamp(strain ?? 0, 0, 21)
        if let m = model { return Stats.clamp(m.strainLinear * s + m.strainQuadratic * s * s, 0, 2 * 3600) }
        return (s / 21) * 45 * 60
    }

    /// Fraction of a night's unmet need carried into the next night's target. NOOP selected 0.55
    /// against 853 consecutive exported WHOOP nights (within 15 min of WHOOP's own debt on 93 %).
    static let debtCarry = 0.55
    static let debtDeadbandSec = 600.0
    static let debtCapSec = 4.0 * 3600

    /// Debt carried into tonight, from the previous night's full need and what was slept.
    static func nextDebtSec(previousNeedSec: Double, creditedSleepSec: Double, carry: Double = debtCarry) -> Double {
        let d = carry * max(0, previousNeedSec - creditedSleepSec)
        return d < debtDeadbandSec ? 0 : min(d, debtCapSec)
    }

    static func needSec(baselineSec: Double, priorStrain: Double?, debtSec: Double, napSec: Double,
                        model: Calibration.NeedModel? = nil) -> Double {
        Stats.clamp(baselineSec + strainBonusSec(priorStrain, model: model) + debtSec - napSec, 5 * 3600, 12 * 3600)
    }

    /// Hours slept against the need, 0–100.
    static func hoursVsNeed(asleepSec: Int, needSec: Double) -> Double? {
        guard needSec > 0 else { return nil }
        return Stats.clamp(Double(asleepSec) / needSec * 100, 0, 100)
    }

    /// Sub-score of the "high stress during sleep" share (0 % → 100, 20 % and more → 0).
    static func stressScore(_ highStressPct: Double?) -> Double {
        guard let p = highStressPct else { return 100 }
        return Stats.clamp(100 - p * 5, 0, 100)
    }

    /// WHOOP's composite sleep score, 0–100.
    static func performance(hoursVsNeed: Double, consistency: Double?, efficiency: Double,
                            highStressPct: Double?, weights w: PerformanceWeights = PerformanceWeights()) -> Double {
        // A missing consistency (first nights) hands its weight to the hours term.
        let c = consistency ?? hoursVsNeed
        let v = w.hours * hoursVsNeed + w.consistency * c + w.efficiency * efficiency
            + w.stress * stressScore(highStressPct) + w.intercept
        return Stats.clamp(v, 0, 100)
    }

    /// Sleep consistency over the last 4 nights: the Sleep Regularity Index (Phillips et al.
    /// 2017) — the probability of being in the same state (asleep / awake) at the same clock
    /// time on consecutive days, rescaled so that chance is 0 and identical nights are 100.
    static func consistency(_ nights: [(start: Int, end: Int)], tz: (Int) -> Int) -> Double? {
        let ns = Array(nights.suffix(4))
        guard ns.count >= 2 else { return nil }
        func mask(_ n: (start: Int, end: Int)) -> [Bool] {
            var m = [Bool](repeating: false, count: 1440)
            let a = SleepSpine.secOfDay(n.start + tz(n.start)) / 60
            let len = max(1, min(1440, (n.end - n.start) / 60))
            for k in 0..<len { m[(a + k) % 1440] = true }
            return m
        }
        var same = 0, total = 0
        var prev = mask(ns[0])
        for i in 1..<ns.count {
            let cur = mask(ns[i])
            for k in 0..<1440 where prev[k] == cur[k] { same += 1 }
            total += 1440
            prev = cur
        }
        guard total > 0 else { return nil }
        return Stats.clamp(-100 + 200 * Double(same) / Double(total), 0, 100)
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

    /// One optimal value inside the band, rising linearly with the recovery
    /// (a real WHOOP day: 45 % → 10,8): the "Objectif d'effort" of an activity.
    static func optimal(for r: Double?) -> Double? {
        guard let r, let band = forRecovery(r) else { return nil }
        let v = 4.95 + 0.13 * Stats.clamp(r, 0, 100)
        return (Stats.clamp(v, band.lowerBound, band.upperBound) * 10).rounded() / 10
    }
}
