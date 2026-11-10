import Foundation

/// 4-class sleep staging (wake / light / deep / REM) on 30 s epochs.
///
/// Adapted from NOOP's `SleepStagerV2` recipe (PolyForm Noncommercial 1.0.0,
/// Required Notice: Copyright 2026 NoopApp): per-night z-scored cardiorespiratory and motion
/// emissions, a deep-sleep gate on 11-minute HR flatness, a soft sleep-cycle prior, an RSA
/// breathing-regularity term, a night-relative motion wake gate and Viterbi smoothing with a
/// sticky transition matrix. Coefficients are a-priori physiology, not fitted to labels.
/// These are approximations, not polysomnography.
enum SleepStager {
    static let stages: [SleepStage] = [.deep, .rem, .light, .wake]

    static let baseLogPrior: [SleepStage: Double] = [
        .light: log(0.50), .deep: log(0.15), .rem: log(0.22), .wake: log(0.10),
    ]
    static let deepGateThresh = 0.25
    static let deepGateSlope = 5.0
    static let jerkFloorMoveMult = 38.0
    static let jerkFloorGateMult = 55.0
    static let motionGateBoost = 2.0
    static let respWeight = 0.6
    static let remLatencyPenalty = 3.0
    static let remLatencyMinutes = 60.0
    static let onsetSustainedEpochs = 10

    static let transition: [SleepStage: [SleepStage: Double]] = [
        .deep: [.deep: 0.86, .rem: 0.007, .light: 0.126, .wake: 0.007],
        .rem: [.deep: 0.005, .rem: 0.88, .light: 0.10, .wake: 0.015],
        .light: [.deep: 0.06, .rem: 0.06, .light: 0.85, .wake: 0.03],
        .wake: [.deep: 0.0, .rem: 0.0, .light: 0.10, .wake: 0.90],
    ]

    struct Epoch {
        let start: Int
        let hr: Double?
        let hrVar: Double?
        let hrFlat11: Double?
        let moveFrac: Double
        let jerkMax: Double
        let respReg: Double?
        let clock: Double
        let jerkScale: Double
        let minutes: Double
    }

    static let padLo = 330
    static let padHi = 390

    /// Stage `[start, end)` from the ts-sorted samples (any superset of the window is fine).
    /// - Parameter priors: the wearer's own typical stage shares (from their WHOOP nights), used in
    ///   place of the population base rates.
    static func stage(samples: [HistorySample], start: Int, end: Int,
                      priors: Calibration.StageShares? = nil) -> [StageSegment] {
        let slice = TimeIndex.slice(samples, from: start - padLo, to: end + padHi)
        let feats = features(slice, start: start, end: end)
        guard !feats.isEmpty else { return [] }
        let labels = stageEpochs(feats, priors: logPriors(priors))
        // One segment per staged epoch. A second we did not observe has no stage: an epoch with
        // no heart rate is skipped (a still strap with no pulse is not sleep), and a coverage
        // hole is left open instead of being carried by the previous label.
        var segs: [StageSegment] = []
        for (i, f) in feats.enumerated() where f.hr != nil {
            var s = f.start
            if i == 0 && f.start - start < 30 { s = start }
            var e = f.start + 30
            if i == feats.count - 1 {
                if end - e < 30 { e = end }
            } else if feats[i + 1].start - f.start <= 60 {
                e = feats[i + 1].start
            }
            s = max(s, start)
            e = min(e, end)
            guard e > s else { continue }
            if let last = segs.last, last.stage == labels[i], last.end == s {
                segs[segs.count - 1].end = e
            } else {
                segs.append(StageSegment(start: s, end: e, stage: labels[i]))
            }
        }
        return segs
    }

    // MARK: Features

    static func features(_ s: ArraySlice<HistorySample>, start: Int, end: Int) -> [Epoch] {
        guard end > start else { return [] }
        let lo = start - padLo, hi = end + padHi
        let n = hi - lo
        var hr = [Double](repeating: .nan, count: n)
        var gx = [Double](repeating: .nan, count: n), gy = gx, gz = gx
        for x in s {
            let i = x.ts - lo
            guard i >= 0, i < n else { continue }
            if x.hr > 0 { hr[i] = Double(x.hr) }
            if x.hasGravity { gx[i] = Double(x.gx); gy[i] = Double(x.gy); gz[i] = Double(x.gz) }
        }
        // Prefix sums for O(1) windowed HR std.
        var pc = [Int](repeating: 0, count: n + 1), ps = [Double](repeating: 0, count: n + 1), pq = ps
        for i in 0..<n {
            let v = hr[i]
            pc[i + 1] = pc[i] + (v.isNaN ? 0 : 1)
            ps[i + 1] = ps[i] + (v.isNaN ? 0 : v)
            pq[i + 1] = pq[i] + (v.isNaN ? 0 : v * v)
        }
        func stdOf(_ a0: Int, _ b0: Int) -> Double? {
            let a = max(0, a0 - lo), b = min(n, b0 - lo)
            guard b > a else { return nil }
            let c = pc[b] - pc[a]
            guard c >= 2 else { return nil }
            let cn = Double(c), sv = ps[b] - ps[a], sq = pq[b] - pq[a]
            let m = sv / cn
            let v = (sq - 2 * m * sv + cn * m * m) / cn
            return max(0, v).squareRoot()
        }
        let beats = HRV.beats(s)

        struct Raw {
            let start: Int; let hr: Double?; let hrVar: Double?; let hrFlat11: Double?
            let jerks: [Double]; let jerkMax: Double; let respReg: Double?; let clock: Double; let minutes: Double
        }
        var raws: [Raw] = []
        var allJerks: [Double] = []
        let span = Double(max(1, end - start))
        var e = ((start + 29) / 30) * 30
        while e < end {
            var hrs: [Double] = []
            var jerks: [Double] = []
            for t in e..<(e + 30) {
                let i = t - lo
                if !hr[i].isNaN { hrs.append(hr[i]) }
                if i > 0, !gx[i].isNaN, !gx[i - 1].isNaN {
                    let dx = gx[i] - gx[i - 1], dy = gy[i] - gy[i - 1], dz = gz[i] - gz[i - 1]
                    jerks.append((dx * dx + dy * dy + dz * dz).squareRoot())
                }
            }
            if hrs.isEmpty && jerks.isEmpty { e += 30; continue }
            allJerks.append(contentsOf: jerks)
            let rsa = respRegularity(HRV.window(beats, from: e - 90, to: e + 120))
            raws.append(Raw(start: e, hr: Stats.mean(hrs), hrVar: stdOf(e - 150, e + 180),
                            hrFlat11: stdOf(e - 330, e + 390), jerks: jerks, jerkMax: jerks.max() ?? 0,
                            respReg: rsa, clock: Double(e + 15 - start) / span,
                            minutes: Double(e + 15 - start) / 60))
            e += 30
        }
        let jerkScale = Stats.median(allJerks) ?? 1e-6
        let moveThr = jerkScale * jerkFloorMoveMult
        return raws.map { r in
            let moves = r.jerks.filter { $0 > moveThr }.count
            return Epoch(start: r.start, hr: r.hr, hrVar: r.hrVar, hrFlat11: r.hrFlat11,
                         moveFrac: r.jerks.isEmpty ? 0 : Double(moves) / Double(r.jerks.count),
                         jerkMax: r.jerkMax, respReg: r.respReg, clock: r.clock,
                         jerkScale: max(jerkScale, 1e-6), minutes: r.minutes)
        }
    }

    /// RSA breathing regularity: spectral peakedness (peak / band power) in 0.15–0.40 Hz of the
    /// 4 Hz-resampled tachogram. As in the reference recipe, each interval is placed on the
    /// second of the record that carried it (clamped to 300–2000 ms).
    static func respRegularity(_ window: ArraySlice<HRV.Beat>) -> Double? {
        guard window.count >= 12 else { return nil }
        var beats: [(t: Double, v: Double)] = []
        beats.reserveCapacity(window.count)
        for b in window { beats.append((Double(b.ts), min(max(b.rr, 300), 2000))) }
        beats.sort { $0.t != $1.t ? $0.t < $1.t : $0.v < $1.v }
        let t0 = beats[0].t, tN = beats[beats.count - 1].t
        guard tN > t0 else { return nil }
        let n = Int(((tN - t0) / 0.25 - 1e-9).rounded(.up))
        guard n >= 16 else { return nil }
        var y = [Double](repeating: 0, count: n)
        var seg = 0
        for i in 0..<n {
            let tt = t0 + 0.25 * Double(i)
            while seg < beats.count - 2 && beats[seg + 1].t < tt { seg += 1 }
            let ta = beats[seg].t, tb = beats[seg + 1].t
            let va = beats[seg].v, vb = beats[seg + 1].v
            y[i] = tb <= ta ? va : va + min(max((tt - ta) / (tb - ta), 0), 1) * (vb - va)
        }
        let m = y.reduce(0, +) / Double(n)
        for i in 0..<n { y[i] -= m }
        let kLo = Int((0.15 * 0.25 * Double(n)).rounded(.up))
        let kHi = Int((0.40 * 0.25 * Double(n)).rounded(.down))
        guard kHi >= kLo, kLo >= 0 else { return nil }
        var maxP = 0.0, sumP = 0.0
        for k in kLo...kHi {
            // Goertzel: |DFT bin k|² without per-sample trigonometry.
            let coeff = 2 * cos(2 * Double.pi * Double(k) / Double(n))
            var s1 = 0.0, s2 = 0.0
            for j in 0..<n {
                let s0 = y[j] + coeff * s1 - s2
                s2 = s1
                s1 = s0
            }
            let p = max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2)
            sumP += p
            maxP = max(maxP, p)
        }
        return sumP > 0 ? maxP / sumP : nil
    }

    // MARK: Staging

    static func remLatencyGuard(_ minutesSinceOnset: Double) -> Double {
        remLatencyPenalty * min(1, max(0, 1 - minutesSinceOnset / remLatencyMinutes))
    }

    static func cyclePrior(_ c: Double, _ minutesSinceOnset: Double) -> [SleepStage: Double] {
        [.deep: 1.2 * max(0, 1 - c / 0.55),
         .rem: 1.0 * c - remLatencyGuard(minutesSinceOnset),
         .light: 0, .wake: 0]
    }

    static func sustainedOnset(_ labels: [SleepStage]) -> Int? {
        var run = 0
        for i in labels.indices {
            if labels[i] == .wake { run = 0; continue }
            run += 1
            if run >= onsetSustainedEpochs { return i - onsetSustainedEpochs + 1 }
        }
        return nil
    }

    static func viterbi(_ em: [[SleepStage: Double]]) -> [SleepStage] {
        guard let first = em.first else { return [] }
        var logT: [SleepStage: [SleepStage: Double]] = [:]
        for (k, row) in transition { logT[k] = row.mapValues { log(max($0, 1e-9)) } }
        var v = first
        var back: [[SleepStage: SleepStage]] = []
        back.reserveCapacity(em.count)
        for t in 1..<em.count {
            var nv: [SleepStage: Double] = [:]
            var bp: [SleepStage: SleepStage] = [:]
            for s in stages {
                var bestPrev = stages[0]
                var bestVal = v[bestPrev]! + logT[bestPrev]![s]!
                for p in stages.dropFirst() {
                    let val = v[p]! + logT[p]![s]!
                    if val > bestVal { bestVal = val; bestPrev = p }
                }
                nv[s] = bestVal + em[t][s]!
                bp[s] = bestPrev
            }
            v = nv
            back.append(bp)
        }
        var last = stages[0]
        var lastV = v[last]!
        for s in stages.dropFirst() where v[s]! > lastV { lastV = v[s]!; last = s }
        var path = [last]
        for bp in back.reversed() { last = bp[last]!; path.append(last) }
        return path.reversed()
    }

    /// Log-priors from personal stage shares (floored so no stage can be ruled out).
    static func logPriors(_ p: Calibration.StageShares?) -> [SleepStage: Double] {
        guard let p else { return baseLogPrior }
        return [.light: log(max(p.light, 0.20)), .deep: log(max(p.deep, 0.05)),
                .rem: log(max(p.rem, 0.08)), .wake: log(Stats.clamp(p.awake, 0.04, 0.25))]
    }

    static func stageEpochs(_ feats: [Epoch], priors: [SleepStage: Double] = baseLogPrior) -> [SleepStage] {
        guard !feats.isEmpty else { return [] }
        func zfun(_ vals: [Double?]) -> (Double?) -> Double {
            let present = vals.compactMap { $0 }
            guard let m = Stats.mean(present) else { return { _ in 0 } }
            let sd0 = Stats.std(present) ?? 0
            let sd = sd0 == 0 ? 1 : sd0
            return { v in v.map { ($0 - m) / sd } ?? 0 }
        }
        let zhr = zfun(feats.map(\.hr))
        let zhv = zfun(feats.map(\.hrVar))
        let zmv = zfun(feats.map { Optional($0.moveFrac) })
        let zrg = zfun(feats.map(\.respReg))
        let flat = feats.compactMap(\.hrFlat11).sorted()
        func fpct(_ v: Double?) -> Double {
            guard let v, !flat.isEmpty else { return 0.5 }
            var lo = 0, hi = flat.count
            while lo < hi { let mid = (lo + hi) / 2; if flat[mid] <= v { lo = mid + 1 } else { hi = mid } }
            return Double(lo) / Double(flat.count)
        }
        var seq: [[SleepStage: Double]] = []
        seq.reserveCapacity(feats.count)
        for f in feats {
            let zh = zhr(f.hr), zv = zhv(f.hrVar), zm = zmv(f.moveFrac)
            let gate = deepGateSlope * max(0, fpct(f.hrFlat11) - deepGateThresh)
            let quiescent = f.moveFrac <= 0 && f.jerkMax <= f.jerkScale * jerkFloorGateMult
            let cardiac0 = 0.8 * zv + 0.4 * zh
            let cardiac = quiescent ? min(0, cardiac0) : cardiac0
            var em: [SleepStage: Double] = [
                .deep: -1.1 * zv - 0.5 * zm - gate + priors[.deep]!,
                .rem: 0.6 * zv - 0.6 * zm + 0.4 * zh + priors[.rem]!,
                .light: priors[.light]!,
                .wake: 1.0 * zm + cardiac + priors[.wake]!,
            ]
            let pr = cyclePrior(f.clock, .infinity)
            for s in stages { em[s]! += pr[s]! }
            if f.jerkMax > f.jerkScale * jerkFloorGateMult { em[.wake]! += motionGateBoost }
            if let rg = f.respReg {
                let z = zrg(rg)
                em[.deep]! += respWeight * z
                em[.rem]! -= respWeight * z
            }
            seq.append(em)
        }
        let provisional = viterbi(seq)
        let origin = sustainedOnset(provisional).map { feats[$0].minutes } ?? 0
        for i in feats.indices {
            seq[i][.rem]! -= remLatencyGuard(feats[i].minutes - origin)
        }
        return viterbi(seq)
    }
}
