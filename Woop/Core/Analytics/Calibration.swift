import Foundation

/// Small dense least-squares solver (normal equations, Gaussian elimination with pivoting).
enum LinearFit {
    /// Minimise |X·b − y|² + ridge·|b|² (the first column — the intercept — is not penalised).
    static func solve(_ x: [[Double]], _ y: [Double], ridge: Double = 1e-6) -> [Double]? {
        guard let p = x.first?.count, p > 0, x.count == y.count, x.count >= p else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: p + 1), count: p)
        for (row, target) in zip(x, y) {
            guard row.count == p else { return nil }
            for i in 0..<p {
                for j in 0..<p { a[i][j] += row[i] * row[j] }
                a[i][p] += row[i] * target
            }
        }
        for i in 1..<max(1, p) { a[i][i] += ridge }
        a[0][0] += 1e-9
        for col in 0..<p {
            var pivot = col
            for r in (col + 1)..<p where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            for r in 0..<p where r != col {
                let f = a[r][col] / a[col][col]
                if f == 0 { continue }
                for c in col...p { a[r][c] -= f * a[col][c] }
            }
        }
        let b = (0..<p).map { a[$0][p] / a[$0][$0] }
        return b.allSatisfy(\.isFinite) ? b : nil
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3, let ma = Stats.mean(a), let mb = Stats.mean(b) else { return nil }
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for i in a.indices {
            sab += (a[i] - ma) * (b[i] - mb)
            saa += (a[i] - ma) * (a[i] - ma)
            sbb += (b[i] - mb) * (b[i] - mb)
        }
        guard saa > 0, sbb > 0 else { return nil }
        return sab / (saa * sbb).squareRoot()
    }
}

/// Personal calibration learned from the wearer's own WHOOP export.
///
/// WHOOP's formulas are private, but an export lists WHOOP's own inputs AND outputs for every
/// night (HRV, resting HR, respiration, sleep need, debt, performance, consistency, recovery;
/// strain, calories and zone shares for every workout). So the mappings can be FITTED per
/// person, then applied to the nights and days the strap records afterwards. Every fit is
/// cross-validated and kept only when it beats the built-in default; otherwise the default
/// stays. Nothing here invents data: no export → no calibration.
struct Calibration: Codable, Equatable, Sendable {
    static let currentVersion = 2

    struct Fit: Codable, Equatable, Sendable {
        /// Rows used.
        var n: Int
        /// Mean absolute error on held-out rows, in the metric's own unit.
        var mae: Double
        /// Same error with the built-in default.
        var defaultMAE: Double?
    }

    struct NeedModel: Codable, Equatable, Sendable {
        var baseSec: Double
        /// Extra seconds of need per strain point, and per strain point squared.
        var strainLinear: Double
        var strainQuadratic: Double
    }

    struct LinearMap: Codable, Equatable, Sendable {
        var a: Double
        var b: Double
        func apply(_ x: Double) -> Double { a * x + b }
    }

    /// logit(recovery) = intercept + Σ weight · standardized driver.
    struct RecoveryModel: Codable, Equatable, Sendable {
        var intercept: Double
        var wLnHRV: Double
        var wRHR: Double
        var wResp: Double
        var wSleep: Double

        func predict(_ f: Recovery.Features) -> Double {
            let z = intercept + wLnHRV * f.zLnHRV + wRHR * (f.zRHR ?? 0) + wResp * (f.zResp ?? 0)
                + wSleep * (f.sleep ?? 0)
            return 100 / (1 + exp(-z))
        }
    }

    /// Typical share of the time in bed spent in each stage, per WHOOP's own staging.
    struct StageShares: Codable, Equatable, Sendable {
        var awake: Double
        var light: Double
        var deep: Double
        var rem: Double
    }

    var version = Calibration.currentVersion
    /// WHOOP nights in the export.
    var whoopNights = 0
    var lastWhoopDay: String?

    var perfWeights: SleepCoach.PerformanceWeights?
    var perfFit: Fit?
    var need: NeedModel?
    var needFit: Fit?
    var debtCarry: Double?
    var debtFit: Fit?
    var consistency: LinearMap?
    var consistencyFit: Fit?
    var recovery: RecoveryModel?
    var recoveryFit: Fit?
    var strainDenominator: Double?
    var strainFit: Fit?
    var kcalActiveScale: Double?
    var kcalWorkouts = 0
    var stageShares: StageShares?
    var stageNights = 0
    /// Nights measured both by WHOOP and by this app (same date).
    var overlapNights = 0
    /// WHOOP value ÷ local value, and WHOOP − local offsets, from the overlapping nights.
    var hrvScale: Double?
    var rhrOffset: Double?
    var respOffset: Double?

    var isEmpty: Bool { whoopNights == 0 }

    /// How many of the fitted parts are active.
    var activeParts: Int {
        [perfWeights != nil, need != nil, debtCarry != nil, consistency != nil, recovery != nil,
         strainDenominator != nil, kcalActiveScale != nil, stageShares != nil, hrvScale != nil,
         rhrOffset != nil].filter { $0 }.count
    }

    // MARK: Fitting

    /// - Parameters:
    ///   - imported: WHOOP days from the export, ascending by date.
    ///   - computed: days computed locally from the strap (raw, uncalibrated values in `*Raw`).
    static func fit(imported: [DayMetrics], computed: [String: DayMetrics], profile: UserProfile,
                    tz: (Int) -> Int) -> Calibration {
        var c = Calibration()
        let days = imported.sorted { $0.date < $1.date }
        c.whoopNights = days.filter { $0.sleep != nil || $0.recovery != nil }.count
        c.lastWhoopDay = days.last?.date
        guard c.whoopNights > 0 else { return c }
        fitPerformance(days, into: &c)
        fitNeed(days, into: &c)
        fitConsistency(days, tz: tz, into: &c)
        fitRecovery(days, into: &c)
        fitStrain(days, into: &c)
        fitCalories(days, profile: profile, into: &c)
        fitStages(days, into: &c)
        fitOverlap(days, computed: computed, into: &c)
        return c
    }

    private static func mae(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
    }

    /// K-fold cross-validated predictions of a linear model (folds interleaved by row).
    private static func crossValidated(_ x: [[Double]], _ y: [Double], ridge: Double, folds: Int = 5) -> [Double]? {
        guard x.count >= folds * 2 else { return nil }
        var pred = [Double](repeating: 0, count: y.count)
        for f in 0..<folds {
            var tx: [[Double]] = [], ty: [Double] = []
            for i in x.indices where i % folds != f { tx.append(x[i]); ty.append(y[i]) }
            guard let b = LinearFit.solve(tx, ty, ridge: ridge) else { return nil }
            for i in x.indices where i % folds == f {
                pred[i] = zip(b, x[i]).reduce(0) { $0 + $1.0 * $1.1 }
            }
        }
        return pred
    }

    // Sleep performance = a·hours% + b·consistency% + c·efficiency% + d.
    private static func fitPerformance(_ days: [DayMetrics], into c: inout Calibration) {
        var x: [[Double]] = [], y: [Double] = [], defaults: [Double] = []
        for d in days.suffix(120) {
            guard let perf = d.sleepPerformance, let need = d.sleepNeedSec, need > 0, let s = d.sleep,
                  s.asleepSec > 0, s.inBedSec > 0, let cons = d.sleepConsistency else { continue }
            let hours = Stats.clamp(Double(s.asleepSec) / need * 100, 0, 100)
            let eff = Stats.clamp(s.efficiency * 100, 0, 100)
            x.append([1, hours, cons, eff])
            y.append(perf)
            defaults.append(SleepCoach.performance(hoursVsNeed: hours, consistency: cons, efficiency: eff, highStressPct: nil))
        }
        guard x.count >= 21, let b = LinearFit.solve(x, y, ridge: 1e-3),
              let cv = crossValidated(x, y, ridge: 1e-3) else { return }
        let err = mae(cv, y), def = mae(defaults, y)
        c.perfFit = Fit(n: x.count, mae: err, defaultMAE: def)
        guard err <= 4, err < def, b[1] >= 0.3, b[1] <= 1.1, b[2] >= -0.05, b[2] <= 0.5,
              b[3] >= -0.05, b[3] <= 0.6 else { return }
        // The stress part is not in the export: it lives in the intercept (measured at "no stress").
        c.perfWeights = SleepCoach.PerformanceWeights(hours: b[1], consistency: max(0, b[2]), efficiency: max(0, b[3]),
                                                      stress: 0.10, intercept: b[0] - 10)
    }

    // Need (without debt) = base + f(strain of the previous day); debt = carry · unmet need.
    private static func fitNeed(_ days: [DayMetrics], into c: inout Calibration) {
        var s1: [Double] = [], y: [Double] = []
        var dx: [Double] = [], dy: [Double] = []
        for i in 1..<max(1, days.count) {
            let prev = days[i - 1], d = days[i]
            guard DayKey.adding(1, to: prev.date) == d.date, let need = d.sleepNeedSec, need > 3 * 3600 else { continue }
            let debt = d.sleepDebtSec ?? 0
            let prevNaps = Double(prev.naps.reduce(0) { $0 + $1.asleepSec })
            if let strain = prev.strain {
                s1.append(strain)
                y.append(need - debt + prevNaps)
            }
            if let pn = prev.sleepNeedSec, let ps = prev.sleep, d.sleepDebtSec != nil {
                dx.append(max(0, pn - Double(ps.asleepSec)))
                dy.append(debt)
            }
        }
        if s1.count >= 14 {
            let lin = s1.map { [1, $0] }, quad = s1.map { [1, $0 * $0] }
            let base = Stats.median(y) ?? 8 * 3600
            let defaults = s1.map { base + SleepCoach.strainBonusSec($0) - SleepCoach.strainBonusSec(Stats.median(s1)) }
            var best: (NeedModel, Double)?
            if let b = LinearFit.solve(lin, y), b[1] >= 0, let cv = crossValidated(lin, y, ridge: 1e-6) {
                best = (NeedModel(baseSec: b[0], strainLinear: b[1], strainQuadratic: 0), mae(cv, y))
            }
            if let b = LinearFit.solve(quad, y), b[1] >= 0, let cv = crossValidated(quad, y, ridge: 1e-6) {
                let e = mae(cv, y)
                if best == nil || e < best!.1 { best = (NeedModel(baseSec: b[0], strainLinear: 0, strainQuadratic: b[1]), e) }
            }
            if let (model, err) = best {
                c.needFit = Fit(n: s1.count, mae: err / 60, defaultMAE: mae(defaults, y) / 60)
                if err <= 25 * 60, model.baseSec >= 5.5 * 3600, model.baseSec <= 10 * 3600 { c.need = model }
            }
        }
        if dx.count >= 14 {
            let sxx = dx.reduce(0) { $0 + $1 * $1 }
            let sxy = zip(dx, dy).reduce(0) { $0 + $1.0 * $1.1 }
            if sxx > 0 {
                let k = sxy / sxx
                let err = mae(dx.map { k * $0 }, dy), def = mae(dx.map { SleepCoach.debtCarry * $0 }, dy)
                c.debtFit = Fit(n: dx.count, mae: err / 60, defaultMAE: def / 60)
                if k >= 0.2, k <= 0.9, err < def { c.debtCarry = k }
            }
        }
    }

    private static func fitConsistency(_ days: [DayMetrics], tz: (Int) -> Int, into c: inout Calibration) {
        var x: [Double] = [], y: [Double] = []
        for i in days.indices.suffix(180) {
            guard let target = days[i].sleepConsistency, let s = days[i].sleep else { continue }
            var nights: [(start: Int, end: Int)] = []
            for d in days[max(0, i - 6)..<i] where d.date >= DayKey.adding(-4, to: days[i].date) {
                if let p = d.sleep { nights.append((p.start, p.end)) }
            }
            nights.append((s.start, s.end))
            guard nights.count >= 4, let ours = SleepCoach.consistency(nights, tz: tz) else { continue }
            x.append(ours)
            y.append(target)
        }
        guard x.count >= 21, let r = LinearFit.pearson(x, y), r >= 0.5,
              let b = LinearFit.solve(x.map { [1, $0] }, y) else { return }
        let err = mae(x.map { b[0] + b[1] * $0 }, y), def = mae(x, y)
        c.consistencyFit = Fit(n: x.count, mae: err, defaultMAE: def)
        if err < def, b[1] > 0.2, b[1] < 2.5 { c.consistency = LinearMap(a: b[1], b: b[0]) }
    }

    private static func logit(_ pct: Double) -> Double {
        let p = Stats.clamp(pct, 1.5, 98.5) / 100
        return log(p / (1 - p))
    }

    private static func fitRecovery(_ days: [DayMetrics], into c: inout Calibration) {
        var x: [[Double]] = [], y: [Double] = [], truth: [Double] = [], defaults: [Double] = []
        for i in days.indices {
            let d = days[i]
            guard let rec = d.recovery, let hrv = d.hrv, hrv > 0, i >= 5 else { continue }
            let history = Array(days[max(0, i - 60)..<i])
            let b = Recovery.baselines(history: history)
            let inputs = Recovery.Inputs(hrv: hrv, rhr: d.rhr, resp: d.respRate, sleepPerformance: d.sleepPerformance,
                                         skinTempDev: nil)
            guard let f = Recovery.features(inputs, b) else { continue }
            x.append([1, f.zLnHRV, f.zRHR ?? 0, f.zResp ?? 0, f.sleep ?? 0])
            y.append(logit(rec))
            truth.append(rec)
            defaults.append(Recovery.score(inputs, b) ?? 58)
        }
        guard x.count >= 30, let b = LinearFit.solve(x, y, ridge: 0.5),
              let cv = crossValidated(x, y, ridge: 0.5) else { return }
        let cvRec = cv.map { 100 / (1 + exp(-$0)) }
        let err = mae(cvRec, truth), def = mae(defaults, truth)
        c.recoveryFit = Fit(n: x.count, mae: err, defaultMAE: def)
        // Physiology must point the right way: more HRV → more recovery, higher resting HR → less.
        guard err < def, err <= 14, b[1] > 0, b[2] <= 0.15, b[4] >= -0.15 else { return }
        c.recovery = RecoveryModel(intercept: b[0], wLnHRV: b[1], wRHR: min(b[2], 0), wResp: b[3], wSleep: max(b[4], 0))
    }

    /// Zone-minutes of a WHOOP workout from its zone shares (zones 1…5 → weights 1…5).
    static func zoneLoad(_ a: ActivityRecord) -> Double {
        var load = 0.0
        var zoned = 0
        for z in 1...5 where z < a.zoneSeconds.count {
            load += Double(z) * Double(a.zoneSeconds[z]) / 60
            zoned += a.zoneSeconds[z]
        }
        // The rest of the workout sat just under zone 1 (≈ 36 % of the reserve on average).
        load += 0.2 * Double(max(0, a.durationSec - zoned)) / 60
        return load
    }

    private static func fitStrain(_ days: [DayMetrics], into c: inout Calibration) {
        var xs: [Double] = [], ss: [Double] = []
        for d in days {
            for a in d.activities where a.source == .imported {
                guard let s = a.strain, s >= 8, s < 20.5 else { continue }
                let load = zoneLoad(a)
                guard load > 5 else { continue }
                xs.append(log(load + 1))
                ss.append(s)
            }
        }
        guard xs.count >= 8 else { return }
        let sxx = xs.reduce(0) { $0 + $1 * $1 }
        let sxs = zip(xs, ss).reduce(0) { $0 + $1.0 * $1.1 }
        guard sxx > 0, sxs > 0 else { return }
        let lnD = Strain.maxStrain * sxx / sxs
        let d = exp(lnD)
        let err = mae(xs.map { Strain.maxStrain * $0 / lnD }, ss)
        let def = mae(xs.map { Strain.maxStrain * $0 / log(Strain.defaultDenominator) }, ss)
        c.strainFit = Fit(n: xs.count, mae: err, defaultMAE: def)
        if d >= 1500, d <= 40_000, err < def { c.strainDenominator = d }
    }

    private static func fitCalories(_ days: [DayMetrics], profile: UserProfile, into c: inout Calibration) {
        let peaks = days.flatMap { $0.activities.compactMap(\.maxHR) }.sorted(by: >)
        var maxHR = profile.tanakaMaxHR
        if let o = profile.maxHROverride, o > 100 { maxHR = Double(o) }
        else if peaks.count >= 3 { maxHR = max(maxHR, min(Double(peaks[1]), 215)) }
        var ratios: [Double] = []
        for d in days {
            let rest = d.rhr ?? 60
            for a in d.activities where a.source == .imported {
                guard let kcal = a.calories, let hr = a.avgHR, a.durationSec >= 15 * 60 else { continue }
                let minutes = Double(a.durationSec) / 60
                let basal = profile.bmr / 1440 * minutes
                let model = Strain.kcalForMinute(hr: hr, asleep: false, rest: rest, maxHR: maxHR, profile: profile).active * minutes
                guard model > 20, kcal - basal > 20 else { continue }
                ratios.append((kcal - basal) / model)
            }
        }
        c.kcalWorkouts = ratios.count
        guard ratios.count >= 8, let m = Stats.median(ratios) else { return }
        c.kcalActiveScale = Stats.clamp(m, 0.5, 1.8)
    }

    private static func fitStages(_ days: [DayMetrics], into c: inout Calibration) {
        var aw: [Double] = [], li: [Double] = [], de: [Double] = [], re: [Double] = []
        for d in days.suffix(90) {
            guard let s = d.sleep, s.deepSec + s.remSec > 0, s.lightSec > 0 else { continue }
            let total = Double(s.awakeSec + s.lightSec + s.deepSec + s.remSec)
            guard total >= 2 * 3600 else { continue }
            aw.append(Double(s.awakeSec) / total); li.append(Double(s.lightSec) / total)
            de.append(Double(s.deepSec) / total); re.append(Double(s.remSec) / total)
        }
        c.stageNights = aw.count
        guard aw.count >= 7, let a = Stats.mean(aw), let l = Stats.mean(li), let d = Stats.mean(de),
              let r = Stats.mean(re) else { return }
        c.stageShares = StageShares(awake: a, light: l, deep: d, rem: r)
    }

    private static func fitOverlap(_ days: [DayMetrics], computed: [String: DayMetrics], into c: inout Calibration) {
        var hrv: [Double] = [], rhr: [Double] = [], resp: [Double] = []
        var n = 0
        for d in days {
            guard let local = computed[d.date], local.sleep != nil else { continue }
            n += 1
            if let w = d.hrv, let l = local.hrvRaw, l > 0, w > 0 { hrv.append(w / l) }
            if let w = d.rhr, let l = local.rhrRaw { rhr.append(w - l) }
            if let w = d.respRate, let l = local.respRaw { resp.append(w - l) }
        }
        c.overlapNights = n
        if hrv.count >= 5, let m = Stats.median(hrv) { c.hrvScale = Stats.clamp(m, 0.5, 1.6) }
        if rhr.count >= 5, let m = Stats.median(rhr) { c.rhrOffset = Stats.clamp(m, -8, 8) }
        if resp.count >= 5, let m = Stats.median(resp) { c.respOffset = Stats.clamp(m, -2.5, 2.5) }
    }
}
