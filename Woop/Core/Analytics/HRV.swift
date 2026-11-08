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
}

/// Beat-to-beat analysis on the strap's R-R intervals.
///
/// The strap reports up to 4 intervals per second and many seconds report none, so the
/// series is GAPPED: two reported intervals are only successive beats when the time between
/// their records agrees with the interval itself. RMSSD across a gap would be meaningless,
/// so successive differences are only taken between beats proven adjacent.
enum HRV {
    struct Beat {
        let ts: Int          // record second
        let rr: Double       // ms
        let adjacent: Bool   // directly follows the previous beat in this list
    }

    /// Ordered beats from a ts-sorted slice.
    static func beats(_ samples: ArraySlice<HistorySample>) -> [Beat] {
        var out: [Beat] = []
        out.reserveCapacity(samples.count)
        var lastTs: Int?
        for s in samples where s.rrCount > 0 {
            let rr = s.rr
            for (k, v) in rr.enumerated() {
                var adj = false
                if k > 0 {
                    adj = true
                } else if let lt = lastTs {
                    let dt = s.ts - lt
                    adj = (1...2).contains(dt) && abs(Double(v) - Double(dt) * 1000) < 950
                }
                out.append(Beat(ts: s.ts, rr: Double(v), adjacent: adj))
            }
            lastTs = s.ts
        }
        return out
    }

    static func window(_ beats: [Beat], from: Int, to: Int) -> ArraySlice<Beat> {
        let a = TimeIndex.lowerBound(beats, from) { $0.ts }
        let b = TimeIndex.lowerBound(beats, to) { $0.ts }
        return beats[a..<max(a, b)]
    }

    /// Successive differences between proven-adjacent beats (first beat of the slice is only a
    /// reference), with the Malik 20 % ectopic rule and a 300–2000 ms physiological gate.
    static func successiveDiffs(_ b: ArraySlice<Beat>) -> [Double] {
        var d: [Double] = []
        var prev: Beat?
        for x in b {
            defer { prev = x }
            guard let p = prev, x.adjacent else { continue }
            guard (300...2000).contains(p.rr), (300...2000).contains(x.rr) else { continue }
            guard abs(x.rr - p.rr) <= 0.2 * p.rr else { continue }
            d.append(x.rr - p.rr)
        }
        return d
    }

    static func rmssd(_ diffs: [Double]) -> Double? {
        guard !diffs.isEmpty else { return nil }
        return (diffs.reduce(0) { $0 + $1 * $1 } / Double(diffs.count)).squareRoot()
    }

    /// RMSSD per window across `[from, to)`; a window needs ≥ `minDiffs` clean differences.
    static func windowedRMSSD(_ beats: [Beat], from: Int, to: Int,
                              window: Int = 300, minDiffs: Int = 20) -> [(start: Int, value: Double)] {
        var out: [(Int, Double)] = []
        var w = from
        while w < to {
            let end = min(w + window, to)
            let b = Self.window(beats, from: w, to: end)
            // Integrity: more beat-time than wall time means duplicated/interleaved beats.
            let covered = b.reduce(0) { $0 + $1.rr } / 1000
            if end - w >= window / 2, covered <= Double(end - w) * 1.10 {
                let d = successiveDiffs(b)
                if d.count >= minDiffs, let v = rmssd(d), v >= 5, v <= 250 { out.append((w, v)) }
            }
            w += window
        }
        return out
    }

    /// Respiratory rate (breaths/min) from respiratory sinus arrhythmia: the dominant
    /// 0.10–0.50 Hz peak of the 4 Hz-resampled tachogram, median over well-covered windows.
    static func respiratoryRate(_ beats: [Beat], from: Int, to: Int, window: Int = 240) -> Double? {
        var estimates: [Double] = []
        var w = from
        while w + window <= to {
            if let r = rsaRate(Self.window(beats, from: w, to: w + window), window: window) { estimates.append(r) }
            w += window / 2
        }
        guard estimates.count >= 3 else { return nil }
        return Stats.median(estimates)
    }

    static func rsaRate(_ beats: ArraySlice<Beat>, window: Int) -> Double? {
        guard beats.count >= 40 else { return nil }
        // Reconstruct beat times along adjacent runs (each run re-anchored on its record second).
        var times: [Double] = []
        var values: [Double] = []
        var t = 0.0
        var anchored = false
        for b in beats where (300...2000).contains(b.rr) {
            if !b.adjacent || !anchored {
                t = Double(b.ts)
                anchored = true
            } else {
                t += b.rr / 1000
            }
            times.append(t)
            values.append(b.rr)
        }
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
            y[i] = tb <= ta ? vs[seg] : vs[seg] + (tt - ta) / (tb - ta) * (vs[seg + 1] - vs[seg])
        }
        let mean = y.reduce(0, +) / Double(n)
        let denom = Double(n - 1)
        for i in 0..<n { y[i] = (y[i] - mean) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / denom)) }
        let kLo = Int((0.10 * Double(n) / fs).rounded(.up))
        let kHi = Int((0.50 * Double(n) / fs).rounded(.down))
        guard kHi > kLo else { return nil }
        var best = 0.0, bestK = kLo, total = 0.0
        for k in kLo...kHi {
            // Goertzel: power at bin k without per-sample trig.
            let coeff = 2 * cos(2 * Double.pi * Double(k) / Double(n))
            var s1 = 0.0, s2 = 0.0
            for j in 0..<n {
                let s0 = y[j] + coeff * s1 - s2
                s2 = s1
                s1 = s0
            }
            let p = s1 * s1 + s2 * s2 - coeff * s1 * s2
            total += p
            if p > best { best = p; bestK = k }
        }
        guard total > 0, best / total >= 0.08 else { return nil }
        let brpm = Double(bestK) * fs / Double(n) * 60
        return (6...30).contains(brpm) ? brpm : nil
    }
}
