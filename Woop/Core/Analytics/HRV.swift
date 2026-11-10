import Foundation

/// Binary search helpers over ts-sorted collections.
enum TimeIndex {
    /// First index whose ts >= t.
    static func lowerBound<C: RandomAccessCollection>(_ c: C, _ t: Int, ts: (C.Element) -> Int) -> C.Index {
        var lo = c.startIndex, hi = c.endIndex
        while lo < hi {
            let mid = c.index(lo, offsetBy: c.distance(from: lo, to: hi) / 2)
            if ts(c[mid]) < t { lo = c.index(after: mid) } else { hi = mid }
        }
        return lo
    }

    static func slice(_ samples: [HistorySample], from: Int, to: Int) -> ArraySlice<HistorySample> {
        let a = lowerBound(samples, from) { $0.ts }
        let b = lowerBound(samples, to) { $0.ts }
        return samples[a..<max(a, b)]
    }

    static func slice(_ samples: ArraySlice<HistorySample>, from: Int, to: Int) -> ArraySlice<HistorySample> {
        let a = lowerBound(samples, from) { $0.ts }
        let b = lowerBound(samples, to) { $0.ts }
        return samples[a..<max(a, b)]
    }
}

/// Beat-to-beat analysis on the strap's R-R intervals (pulse-rate variability).
///
/// The strap reports up to 4 intervals per second and drops beats it cannot time, so the
/// series is GAPPED. Differencing straight down a compacted list manufactures one difference
/// per missing beat, spanning it — measured by OpenStrap on real nights, that inflated the
/// nightly RMSSD by 2–13 % on WHOOP 4.0 and by 51–102 % on WHOOP 5.0 / MG. So every difference
/// here is taken inside a CONTIGUOUS run of clean beats only (NOOP `cleanRRGapAware`,
/// OpenStrap `_cleanWindowRuns`).
enum HRV {
    struct Beat: Equatable {
        /// Second of the record that carried the interval.
        let ts: Int
        /// Interval, ms.
        let rr: Double
    }

    static let rrMin = 300.0
    static let rrMax = 2000.0
    static let ectopicThreshold = 0.20
    static let ectopicRadius = 2
    static let minDiffsPerWindow = 20
    static let coverageCeiling = 1.10
    static let coverageMinSpanSec = 600.0
    static let coverageMaxRR = 2400.0

    /// Beats in record order from a ts-sorted slice.
    static func beats(_ samples: ArraySlice<HistorySample>) -> [Beat] {
        var out: [Beat] = []
        out.reserveCapacity(samples.count)
        for s in samples where s.rrCount > 0 {
            let n = Int(s.rrCount)
            if n > 0 { out.append(Beat(ts: s.ts, rr: Double(s.rr0))) }
            if n > 1 { out.append(Beat(ts: s.ts, rr: Double(s.rr1))) }
            if n > 2 { out.append(Beat(ts: s.ts, rr: Double(s.rr2))) }
            if n > 3 { out.append(Beat(ts: s.ts, rr: Double(s.rr3))) }
        }
        return out
    }

    static func window(_ beats: [Beat], from: Int, to: Int) -> ArraySlice<Beat> {
        let a = TimeIndex.lowerBound(beats, from) { $0.ts }
        let b = TimeIndex.lowerBound(beats, to) { $0.ts }
        return beats[a..<max(a, b)]
    }

    private static func median(_ v: inout [Double]) -> Double {
        v.sort()
        let n = v.count
        return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2
    }

    /// Contiguous runs of clean intervals: range filter 300–2000 ms, then Malik-style ectopic
    /// rejection (more than 20 % away from the median of the 4 surrounding beats). BOTH filters
    /// break a run, and so does a real dropout between two beats that survive.
    static func cleanRuns(_ b: ArraySlice<Beat>) -> [[Double]] {
        var nn: [Double] = [], at: [Int] = [], nnTs: [Int] = []
        nn.reserveCapacity(b.count); at.reserveCapacity(b.count); nnTs.reserveCapacity(b.count)
        for (i, x) in b.enumerated() where x.rr >= rrMin && x.rr <= rrMax {
            nn.append(x.rr); at.append(i); nnTs.append(x.ts)
        }
        var runs: [[Double]] = []
        var run: [Double] = []
        var lastKept = -2
        var lastTs = 0
        var neighbours: [Double] = []
        neighbours.reserveCapacity(2 * ectopicRadius)
        for i in 0..<nn.count {
            var keep = true
            if nn.count > ectopicRadius {
                let lo = max(0, i - ectopicRadius), hi = min(nn.count - 1, i + ectopicRadius)
                neighbours.removeAll(keepingCapacity: true)
                for j in lo...hi where j != i { neighbours.append(nn[j]) }
                if neighbours.count >= 2 {
                    let med = median(&neighbours)
                    if med > 0 { keep = abs(nn[i] - med) / med <= ectopicThreshold }
                }
            }
            if !keep {
                if !run.isEmpty { runs.append(run); run = [] }
                continue
            }
            // Record stamps are whole seconds, so two successive beats can sit up to ~1 s
            // further apart than the interval itself with no dropout at all.
            if !run.isEmpty && (at[i] != lastKept + 1 || Double(nnTs[i] - lastTs) * 1000 > nn[i] + 1000) {
                runs.append(run)
                run = []
            }
            run.append(nn[i])
            lastKept = at[i]
            lastTs = nnTs[i]
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }

    static func diffRuns(_ runs: [[Double]]) -> [[Double]] {
        var out: [[Double]] = []
        for r in runs where r.count >= 2 {
            var d: [Double] = []
            d.reserveCapacity(r.count - 1)
            for i in 1..<r.count { d.append(r[i] - r[i - 1]) }
            out.append(d)
        }
        return out
    }

    static func rmssd(_ diffs: [Double]) -> Double? {
        guard !diffs.isEmpty else { return nil }
        return (diffs.reduce(0) { $0 + $1 * $1 } / Double(diffs.count)).squareRoot()
    }

    /// Σ plausible R-R ÷ elapsed time. Above ~1 is impossible for one heart: it flags beats
    /// stored twice or two interleaved streams. nil below 2 beats or a 10-minute span.
    static func coverage(_ b: ArraySlice<Beat>) -> Double? {
        guard b.count >= 2, let first = b.first, let last = b.last else { return nil }
        func counts(_ v: Double) -> Bool { v >= rrMin && v <= coverageMaxRR }
        let span = Double(last.ts - first.ts) + (counts(first.rr) ? first.rr / 1000 : 0)
        guard span >= coverageMinSpanSec else { return nil }
        var sum = 0.0
        for x in b where counts(x.rr) { sum += x.rr }
        return sum / 1000 / span
    }

    /// Lag-1 autocorrelation of the successive differences, pooled over contiguous runs.
    /// Near 0 on a smooth tachogram, −0.5 for pure beat-timing noise: a quality figure for the
    /// night's RMSSD (OpenStrap `nnDiffAcf1`).
    static func diffAcf1(_ runs: [[Double]]) -> Double? {
        var n = 0
        var sum = 0.0
        for r in runs { for d in r { sum += d; n += 1 } }
        guard n >= 30 else { return nil }
        let m = sum / Double(n)
        var cov = 0.0, varSum = 0.0
        for r in runs {
            for i in 0..<r.count {
                let a = r[i] - m
                varSum += a * a
                if i > 0 { cov += (r[i - 1] - m) * a }
            }
        }
        return varSum > 0 ? cov / varSum : nil
    }

    struct SessionHRV: Equatable {
        /// Median RMSSD of the valid 5-minute windows, ms.
        var rmssd: Double
        var windows: Int
        var thinWindows = 0
        var overCountedWindows = 0
        var acf1: Double?
        var coverage: Double?
        /// True when no window reached the beat floor and the night's differences were pooled.
        var pooled = false
    }

    /// Nightly HRV: the RMSSD of consecutive 5-minute windows across the night's in-bed spans,
    /// summarised by their MEDIAN. A window counts only with ≥ 20 clean successive differences
    /// (ultra-short RMSSD floor, Munoz 2015 / Baek 2015) and no more beat-time than wall time.
    ///
    /// Both reference projects window the night this way (NOOP `sessionAvgHRV`, OpenStrap
    /// `sleepSessionWindowedRmssd` / `nocturnalRmssd`). The median is OpenStrap's robust
    /// variant: on real nights NOOP found the whole-night MEAN reads above WHOOP's own value —
    /// a few windows inflated by residual artefacts pull a mean up, not a median.
    static func sessionRMSSD(_ beats: [Beat], spans: [(start: Int, end: Int)], window: Int = 300,
                             minDiffs: Int = minDiffsPerWindow) -> SessionHRV? {
        var rmssds: [Double] = []
        var pooledRuns: [[Double]] = []
        var thin = 0, over = 0
        var covSum = 0.0, covSpan = 0.0
        for span in spans where span.end > span.start {
            let all = Self.window(beats, from: span.start, to: span.end)
            guard !all.isEmpty else { continue }
            if let c = coverage(all) {
                let sp = Double(all.last!.ts - all.first!.ts)
                covSum += c * sp
                covSpan += sp
            }
            var w = span.start
            while w < span.end {
                let wEnd = min(w + window, span.end)
                let b = Self.window(beats, from: w, to: wEnd)
                defer { w += window }
                guard !b.isEmpty else { continue }
                var banked = 0.0
                for x in b where x.rr >= rrMin && x.rr <= coverageMaxRR { banked += x.rr }
                let overhang = (b.first!.rr >= rrMin && b.first!.rr <= coverageMaxRR) ? b.first!.rr : 0
                if banked > coverageCeiling * (Double(wEnd - w) * 1000 + overhang) { over += 1; continue }
                let diffs = diffRuns(cleanRuns(b))
                var ssd = 0.0
                var nd = 0
                for r in diffs { for d in r { ssd += d * d; nd += 1 } }
                pooledRuns.append(contentsOf: diffs)
                if nd < minDiffs { thin += 1; continue }
                rmssds.append((ssd / Double(nd)).squareRoot())
            }
        }
        let cov = covSpan > 0 ? covSum / covSpan : nil
        // More beat-time than elapsed time over the whole night: beats stored twice or two
        // interleaved streams — no honest RMSSD exists for it.
        if let c = cov, c > coverageCeiling { return nil }
        let acf1 = diffAcf1(pooledRuns)
        if !rmssds.isEmpty {
            return SessionHRV(rmssd: median(&rmssds), windows: rmssds.count,
                              thinWindows: thin, overCountedWindows: over, acf1: acf1, coverage: cov)
        }
        // Sparse beat stream: no window reaches the floor on its own; pool the whole night.
        var ssd = 0.0
        var nd = 0
        for r in pooledRuns { for d in r { ssd += d * d; nd += 1 } }
        guard nd >= 2 * minDiffs else { return nil }
        return SessionHRV(rmssd: (ssd / Double(nd)).squareRoot(), windows: 0, thinWindows: thin,
                          overCountedWindows: over, acf1: acf1, coverage: cov, pooled: true)
    }

    static func sessionRMSSD(_ beats: [Beat], start: Int, end: Int) -> SessionHRV? {
        sessionRMSSD(beats, spans: [(start, end)])
    }

    // MARK: Respiration (RSA)

    /// Beat times along contiguous stretches (each stretch re-anchored on its record second).
    static func tachogram(_ beats: ArraySlice<Beat>) -> (t: [Double], v: [Double]) {
        var times: [Double] = [], values: [Double] = []
        times.reserveCapacity(beats.count); values.reserveCapacity(beats.count)
        var t = 0.0
        var lastTs: Int?
        for b in beats where b.rr >= rrMin && b.rr <= rrMax {
            if let lt = lastTs, Double(b.ts - lt) * 1000 <= b.rr + 1000 {
                t += b.rr / 1000
                // Accumulated beat time may not drift away from the record clock.
                if abs(t - Double(b.ts)) > 2 { t = Double(b.ts) }
            } else {
                t = Double(b.ts)
            }
            lastTs = b.ts
            times.append(t)
            values.append(b.rr)
        }
        return (times, values)
    }

    /// Respiratory rate (breaths/min) from respiratory sinus arrhythmia: the dominant
    /// 0.10–0.50 Hz peak of the 4 Hz-resampled tachogram, median over well-covered windows.
    static func respiratoryRate(_ beats: [Beat], spans: [(start: Int, end: Int)], window: Int = 240) -> Double? {
        var estimates: [Double] = []
        for span in spans {
            var w = span.start
            while w + window <= span.end {
                if let r = rsaRate(Self.window(beats, from: w, to: w + window), window: window) { estimates.append(r) }
                w += window / 2
            }
        }
        guard estimates.count >= 3 else { return nil }
        return Stats.median(estimates)
    }

    static func respiratoryRate(_ beats: [Beat], from: Int, to: Int, window: Int = 240) -> Double? {
        respiratoryRate(beats, spans: [(from, to)], window: window)
    }

    static func rsaRate(_ beats: ArraySlice<Beat>, window: Int) -> Double? {
        guard beats.count >= 40 else { return nil }
        let (times, values) = tachogram(beats)
        let covered = values.reduce(0, +) / 1000
        guard covered >= 0.6 * Double(window), covered <= 1.1 * Double(window) else { return nil }
        let order = times.indices.sorted { times[$0] < times[$1] }
        let ts = order.map { times[$0] }, vs = order.map { values[$0] }
        guard ts.count >= 2, let t0 = ts.first, let tN = ts.last, tN - t0 > 60 else { return nil }
        let fs = 4.0
        let n = Int((tN - t0) * fs)
        guard n >= 256 else { return nil }
        var y = [Double](repeating: 0, count: n)
        var seg = 0
        for i in 0..<n {
            let tt = t0 + Double(i) / fs
            while seg < ts.count - 2 && ts[seg + 1] < tt { seg += 1 }
            let ta = ts[seg], tb = ts[seg + 1]
            y[i] = tb <= ta ? vs[seg] : vs[seg] + min(max((tt - ta) / (tb - ta), 0), 1) * (vs[seg + 1] - vs[seg])
        }
        let mean = y.reduce(0, +) / Double(n)
        let denom = Double(n - 1)
        for i in 0..<n { y[i] = (y[i] - mean) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / denom)) }
        let kLo = Int((0.10 * Double(n) / fs).rounded(.up))
        let kHi = Int((0.50 * Double(n) / fs).rounded(.down))
        guard kHi > kLo else { return nil }
        var best = 0.0, bestK = kLo, total = 0.0
        var powers: [Double] = []
        powers.reserveCapacity(kHi - kLo + 1)
        for k in kLo...kHi {
            // Goertzel: power at bin k without per-sample trig.
            let coeff = 2 * cos(2 * Double.pi * Double(k) / Double(n))
            var s1 = 0.0, s2 = 0.0
            for j in 0..<n {
                let s0 = y[j] + coeff * s1 - s2
                s2 = s1
                s1 = s0
            }
            let p = max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2)
            powers.append(p)
            total += p
            if p > best { best = p; bestK = k }
        }
        guard total > 0, best / total >= 0.08 else { return nil }
        // Parabolic interpolation around the peak bin for a finer estimate than one bin.
        var kf = Double(bestK)
        let i = bestK - kLo
        if i > 0 && i < powers.count - 1 {
            let a = powers[i - 1], b = powers[i], c = powers[i + 1]
            let d = a - 2 * b + c
            if d < 0 { kf += Stats.clamp(0.5 * (a - c) / d, -0.5, 0.5) }
        }
        let brpm = kf * fs / Double(n) * 60
        return (6...30).contains(brpm) ? brpm : nil
    }
}

/// Night-time vitals other than HRV.
enum Vitals {
    /// Resting heart rate of a night: the lowest 30-minute rolling mean of the heart rate inside
    /// the given windows (a window needs ≥ 90 % of its seconds measured), as in OpenStrap
    /// `nocturnalRhr` (Avram 2019; Dial 2025). Falls back to the lowest 5-minute mean on a
    /// patchy night (NOOP `sessionRestingHR`).
    static func restingHR(_ samples: ArraySlice<HistorySample>, windows: [(start: Int, end: Int)],
                          window: Int = 1800, minCoverage: Double = 0.9) -> Double? {
        var best: Double?
        var fallbackBest: Double?
        for w in windows {
            let s = TimeIndex.slice(samples, from: w.start, to: w.end)
            guard !s.isEmpty else { continue }
            // Rolling 30-minute mean over wall-clock time.
            var sum = 0, count = 0
            var lo = s.startIndex
            let firstFullEnd = w.start + window - 1
            let need = Int((minCoverage * Double(window)).rounded(.up))
            for hi in s.indices {
                if s[hi].hr > 0 { sum += Int(s[hi].hr); count += 1 }
                while s[hi].ts - s[lo].ts >= window {
                    if s[lo].hr > 0 { sum -= Int(s[lo].hr); count -= 1 }
                    lo = s.index(after: lo)
                }
                if s[hi].ts < firstFullEnd || count < need || count == 0 { continue }
                let m = Double(sum) / Double(count)
                if best == nil || m < best! { best = m }
            }
            // 5-minute bins (≥ 5 samples, mean ≥ 25 bpm).
            var t = w.start
            var i = s.startIndex
            while t < w.end && i < s.endIndex {
                var bs = 0, bn = 0
                while i < s.endIndex && s[i].ts < t + 300 {
                    if s[i].hr > 0 { bs += Int(s[i].hr); bn += 1 }
                    i = s.index(after: i)
                }
                if bn >= 5 {
                    let m = Double(bs) / Double(bn)
                    if m >= 25 && (fallbackBest == nil || m < fallbackBest!) { fallbackBest = m }
                }
                t += 300
            }
        }
        return best ?? fallbackBest
    }
}
