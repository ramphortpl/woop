import Foundation

/// A continuous in-bed run found by the sleep spine.
struct SleepRun: Equatable, Sendable {
    var start: Int
    /// Exclusive end (last observed second + 1).
    var end: Int
    /// Found from heart rate alone (no motion data for this stretch).
    var hrOnly = false

    var duration: Int { max(0, end - start) }
}

/// Runs that belong to one night: the time between two runs is an awakening, not a new sleep.
struct NightGroup: Equatable, Sendable {
    var runs: [SleepRun]
    /// Minutes asleep across the runs (filled once the runs are staged).
    var asleepMin: Double = 0

    var start: Int { runs.first?.start ?? 0 }
    var end: Int { runs.map(\.end).max() ?? 0 }
    var midsleep: Int { start + (end - start) / 2 }
    var hrOnly: Bool { !runs.isEmpty && runs.allSatisfy(\.hrOnly) }
}

/// Sleep / wake detection ("where are the nights?").
///
/// The method is the one both reference projects converge on (NOOP `SleepStager.detectSleep`,
/// OpenStrap `AdvancedSleepStager.detectSleep` + `segmentSleep`), reimplemented here:
///
/// 1. **Stillness spine** — the change of the gravity vector between two seconds; a second is
///    "in a sleep run" when ≥ 70 % of the surrounding 15 minutes are still (< 0.01 g/s).
/// 2. Runs are closed on a class change or a recording gap > 20 min; runs < 15 min are absorbed
///    by their neighbours; fragments split by a brief stir are re-stitched when the heart rate
///    stays in the sleep band across the gap.
/// 3. Each run must pass: > 60 min (one short pre-dawn tail per night is exempt), ≤ 16 h, a
///    heart rate in the sleep band (widened when the wrist is perfectly quiescent), mostly on
///    the wrist, and — when centred in the daytime — a real resting-heart-rate dip. A re-onset
///    shortly after the morning wake needs the strap's own "asleep" state or a deeper dip.
/// 4. Runs separated by < 60 min (≤ 90 min overnight) form one night; the main night of a day
///    is the group with the most sleep, helped by how close it sits to the usual mid-sleep.
/// 5. The strap's own wake/sleep envelope (WHOOP 5.0 / MG) never creates a night: it only
///    confirms a borderline one and trims a lie-in at the end.
/// 6. Stretches with a heart rate but no motion data (live-only seconds) fall back to a
///    heart-rate-only spine.
enum SleepSpine {
    // Stage-0 constants (shared by both reference implementations).
    static let stillThresholdGPerS = 0.01
    static let stillWindowMin = 15
    static let stillFraction = 0.70
    static let maxGapMin = 20
    static let mergeMin = 15
    static let minSleepMin = 60
    static let minWindowSamples = 3
    static let maxStillCadenceSec = 30.0
    static let hrSleepBaselineMult = 1.05
    static let hrRefineMinSamples = 30
    // Daytime false-sleep guard.
    static let daytimeBandStartHour = 11
    static let daytimeBandEndHour = 20
    static let nightContinuationGapMin = 90
    static let daytimeMinSleepMin = 90
    static let daytimeRestingHRMult = 0.95
    static let maxMainSleepSpanS = 16 * 3600
    // Morning re-onset.
    static let morningStillnessWindowMin = 180
    static let morningReonsetRestingHRMult = 0.90
    static let morningReonsetBandAsleepFrac = 0.6
    // Off-wrist.
    static let offWristHRGapMin = 20
    static let maxOffWristSleepFraction = 0.5
    static let hrDenseSpacingS = 600
    // Fragment bridging.
    static let sparseGravitySpanFrac = 0.5
    static let bridgeGapMin = 90
    static let bridgeActiveMaxMin = 30
    static let bridgeActiveMaxInBandMin = 60
    // Motion-corroborated heart-rate band (elevated-but-motionless nights).
    static let quiescentHRSleepMult = 1.30
    static let quiescentPostureVarG2 = 0.05
    static let quiescentStableFrac = 0.90
    static let quiescentMinStableMinutes = 20
    // Sleep evidence: the strap's own verdict and the heart rate against the sleeping level.
    static let evidenceNeighbourhoodS = 6 * 3600
    static let evidenceBandAccept = 0.5
    static let evidenceBandReject = 0.2
    static let evidenceMinBandCoverage = 0.5
    static let evidenceHRRatioWithBand = 1.30
    static let evidenceHRRatioWeakBand = 1.15
    static let evidenceHRRatioNoBand = 1.20
    static let evidenceHRRatioNoBandLong = 1.30
    static let evidenceLongRunS = 3 * 3600
    /// The strap's envelope only counts as a witness when it is alive: it must have reported
    /// "asleep" for at least this long somewhere in the window. A strap (or firmware) that never
    /// leaves "wake" says nothing about any particular stretch.
    static let bandAliveSleepSec = 30 * 60
    // Edge refinement.
    static let edgeProbeSamples = 30
    static let edgeStillFraction = 0.8
    static let edgeMaxExtendSec = 8 * 60
    static let edgeMaxStepSec = 5
    // Heart-rate-only spine.
    static let hrOnlyAnchorPercentile = 0.10
    static let hrOnlyBandMult = 1.05
    /// Sleeping heart rate swings (REM, late-night cycles) well above its trough: minutes up to
    /// this multiple of the anchor may belong to a run that is anchored in the trough.
    static let hrOnlyExtendedMult = 1.25
    static let hrOnlyMinCoreFraction = 0.25
    static let hrOnlyEpochS = 60
    static let hrOnlyHoleS = 600
    // Night grouping / main-night choice.
    static let groupGapMin = 60
    static let alignmentBonusMin = 90.0
    static let alignmentFullWindowSec = 2 * 3600
    static let alignmentZeroSec = 5 * 3600
    static let coldStartMidsleepSec = 3 * 3600 + 1800
    static let habitualMinDays = 14
    // Strap envelope: end-of-night trim.
    static let bandSleep: Int8 = 2
    static let bandStill: Int8 = 1
    static let minBandCoveragePct = 80
    static let minBandTailCoveragePct = 95
    static let maxBandTailGapSec = 300
    static let maxBandTailStillSec = 60
    static let minBandTrimSec = 600
    static let minNightSec = 3 * 3600

    struct Period: Equatable {
        var sleep: Bool
        var start: Int
        /// Inclusive: timestamp of the last sample of the run.
        var end: Int
        var span: Int { end - start }
    }

    // MARK: - Heart-rate index

    /// Heart rate samples (hr > 0) by time, with O(log n + range) range statistics.
    struct HRIndex {
        var ts: [Int] = []
        var bpm: [UInt8] = []

        var isEmpty: Bool { ts.isEmpty }
        var count: Int { ts.count }

        func bounds(_ a: Int, _ b: Int) -> Range<Int> {
            let lo = TimeIndex.lowerBound(ts, a) { $0 }
            let hi = TimeIndex.lowerBound(ts, b + 1) { $0 }
            return lo..<max(lo, hi)
        }

        /// Count, mean and median of the heart rate in `[a, b]` (inclusive).
        func stats(_ a: Int, _ b: Int) -> (count: Int, mean: Double, median: Double)? {
            let r = bounds(a, b)
            guard !r.isEmpty else { return nil }
            var hist = [Int](repeating: 0, count: 256)
            var sum = 0
            for i in r { hist[Int(bpm[i])] += 1; sum += Int(bpm[i]) }
            return (r.count, Double(sum) / Double(r.count), Self.percentile(hist, total: r.count, p: 0.5, interpolate: true))
        }

        func percentile(_ p: Double) -> Double? {
            guard !bpm.isEmpty else { return nil }
            var hist = [Int](repeating: 0, count: 256)
            for v in bpm { hist[Int(v)] += 1 }
            return Self.percentile(hist, total: bpm.count, p: p, interpolate: false)
        }

        /// Nearest-rank percentile of the heart rate in `[a, b]`.
        func percentile(_ p: Double, from a: Int, to b: Int) -> Double? {
            let r = bounds(a, b)
            guard !r.isEmpty else { return nil }
            var hist = [Int](repeating: 0, count: 256)
            for i in r { hist[Int(bpm[i])] += 1 }
            return Self.percentile(hist, total: r.count, p: p, interpolate: false)
        }

        var median: Double? {
            guard !bpm.isEmpty else { return nil }
            var hist = [Int](repeating: 0, count: 256)
            for v in bpm { hist[Int(v)] += 1 }
            return Self.percentile(hist, total: bpm.count, p: 0.5, interpolate: true)
        }

        /// Percentile from a value histogram. `interpolate` gives the classic median (mean of
        /// the two middle values for an even count); otherwise nearest-rank.
        static func percentile(_ hist: [Int], total: Int, p: Double, interpolate: Bool) -> Double {
            guard total > 0 else { return 0 }
            func valueAt(_ rank: Int) -> Double {
                var acc = 0
                for v in 0..<hist.count {
                    acc += hist[v]
                    if acc > rank { return Double(v) }
                }
                return Double(hist.count - 1)
            }
            if interpolate, total % 2 == 0, p == 0.5 {
                return (valueAt(total / 2 - 1) + valueAt(total / 2)) / 2
            }
            let idx = min(max(Int(Double(total - 1) * p), 0), total - 1)
            return valueAt(idx)
        }

        /// Lowest 5-minute bin mean in `[a, b]` (bins need ≥ 5 samples and a mean ≥ 25 bpm);
        /// falls back to the lowest bin, then to the overall mean.
        func lowestBinMean(_ a: Int, _ b: Int, window: Int = 300) -> Double? {
            let r = bounds(a, b)
            guard !r.isEmpty else { return nil }
            var gated: Double?
            var ungated: Double?
            var total = 0
            var i = r.lowerBound
            var t = a
            while t <= b && i < r.upperBound {
                var sum = 0, n = 0
                while i < r.upperBound && ts[i] < t + window {
                    sum += Int(bpm[i]); n += 1; i += 1
                }
                if n > 0 {
                    let m = Double(sum) / Double(n)
                    total += sum
                    ungated = min(ungated ?? m, m)
                    if n >= 5 && m >= 25 { gated = min(gated ?? m, m) }
                }
                t += window
            }
            if let g = gated { return g }
            if let u = ungated { return u }
            return Double(total) / Double(r.count)
        }
    }

    // MARK: - Entry point

    struct Output {
        var runs: [SleepRun] = []
        /// Median heart rate of the whole window (the sleep band's reference).
        var hrBaseline: Double?
        /// True when the motion stream covers less than half of the heart-rate span.
        var gravitySparse = false
    }

    /// Detect every sleep run in a ts-sorted slice.
    /// - Parameters:
    ///   - tz: seconds east of GMT in effect at a unix time (daytime guards use the local clock).
    ///   - wristOff: `[start, end)` intervals where the strap reported it was off the wrist.
    static func detect(_ samples: ArraySlice<HistorySample>, tz: (Int) -> Int,
                       wristOff: [(start: Int, end: Int)] = []) -> Output {
        var gTs: [Int] = [], gx: [Float] = [], gy: [Float] = [], gz: [Float] = []
        var hr = HRIndex()
        var bandTs: [Int] = [], bandState: [Int8] = []
        gTs.reserveCapacity(samples.count)
        gx.reserveCapacity(samples.count); gy.reserveCapacity(samples.count); gz.reserveCapacity(samples.count)
        hr.ts.reserveCapacity(samples.count); hr.bpm.reserveCapacity(samples.count)
        for s in samples {
            if s.hasGravity { gTs.append(s.ts); gx.append(s.gx); gy.append(s.gy); gz.append(s.gz) }
            if s.hr > 0 { hr.ts.append(s.ts); hr.bpm.append(s.hr) }
            if s.sleepState >= 0 { bandTs.append(s.ts); bandState.append(s.sleepState) }
        }
        var out = Output()
        out.hrBaseline = hr.median
        var runs: [SleepRun] = []
        if !bandIsAlive(bandState) { bandTs = []; bandState = [] }

        if gTs.count >= 2 {
            let sparse = isGravitySparse(gTs: gTs, hr: hr)
            out.gravitySparse = sparse
            let still = classifyStill(gTs: gTs, gx: gx, gy: gy, gz: gz)
            var periods = buildRuns(gTs: gTs, flags: still.flags, sparse: sparse, hr: hr, baseline: out.hrBaseline)
            periods = mergePeriods(periods)
            periods = bridgeFragments(periods, sparse: sparse, hr: hr, baseline: out.hrBaseline)
            periods = refineEdges(periods, gTs: gTs, stillPrefix: still.stillPrefix)
            runs = acceptRuns(periods, hr: hr, baseline: out.hrBaseline, tz: tz, wristOff: wristOff,
                              gTs: gTs, gx: gx, gy: gy, gz: gz, bandTs: bandTs, bandState: bandState)
        }
        // Heart-rate-only spine over the stretches that carry no motion data at all.
        let holeHR = hrOutsideGravity(hr, gTs: gTs)
        if holeHR.count >= minSleepMin * 60 / 4, let anchor = hr.percentile(hrOnlyAnchorPercentile) {
            let hrPeriods = hrOnlyPeriods(holeHR, baseline: anchor)
            for p in hrPeriods where p.sleep && p.span >= minSleepMin * 60 && p.span <= maxMainSleepSpanS {
                let centre = p.start + p.span / 2
                let hour = secOfDay(centre + tz(centre)) / 3600
                if hour >= daytimeBandStartHour && hour < daytimeBandEndHour { continue } // unverifiable by day
                let cand = SleepRun(start: p.start, end: p.end + 1, hrOnly: true)
                if !runs.contains(where: { $0.start < cand.end && cand.start < $0.end }) { runs.append(cand) }
            }
        }
        out.runs = runs.sorted { $0.start < $1.start }
        return out
    }

    /// True when the strap's envelope reported "asleep" for at least `bandAliveSleepSec`.
    static func bandIsAlive(_ states: [Int8]) -> Bool {
        var n = 0
        for v in states where v == bandSleep {
            n += 1
            if n >= bandAliveSleepSec { return true }
        }
        return false
    }

    // MARK: - Stillness spine

    static func medianInterval(_ ts: [Int]) -> Double? {
        guard ts.count >= 2 else { return nil }
        // The cadence is the typical spacing; a few long gaps must not move it.
        var hist: [Int: Int] = [:]
        let step = max(1, ts.count / 20_000)
        var i = step
        var n = 0
        while i < ts.count {
            let d = ts[i] - ts[i - 1]
            if d > 0 { hist[d, default: 0] += 1; n += 1 }
            i += step
        }
        guard n > 0 else { return nil }
        var acc = 0
        for k in hist.keys.sorted() {
            acc += hist[k]!
            if acc * 2 >= n { return Double(k) }
        }
        return nil
    }

    static func isGravitySparse(gTs: [Int], hr: HRIndex) -> Bool {
        guard gTs.count >= 2, hr.count >= 2 else { return false }
        let hrSpan = hr.ts[hr.count - 1] - hr.ts[0]
        guard hrSpan > 0 else { return false }
        let gravSpan = gTs[gTs.count - 1] - gTs[0]
        if Double(gravSpan) < sparseGravitySpanFrac * Double(hrSpan) { return true }
        var largest = 0
        for i in 1..<gTs.count { largest = max(largest, gTs[i] - gTs[i - 1]) }
        return largest > maxGapMin * 60
    }

    /// Per-sample "inside a still window" flags, plus the running count of still samples
    /// (`stillPrefix[i]` = still samples before index i) for edge refinement.
    static func classifyStill(gTs: [Int], gx: [Float], gy: [Float], gz: [Float]) -> (flags: [Bool], stillPrefix: [Int32]) {
        let n = gTs.count
        guard n >= 2, let cadence = medianInterval(gTs), cadence <= maxStillCadenceSec else {
            return ([Bool](repeating: false, count: n), [Int32](repeating: 0, count: n + 1))
        }
        let window = max(minWindowSamples, Int(Double(stillWindowMin * 60) / cadence))
        let half = window / 2
        let cut = stillThresholdGPerS * cadence
        var prefix = [Int32](repeating: 0, count: n + 1)
        for i in 0..<n {
            var still = true
            if i > 0 {
                let dx = Double(gx[i] - gx[i - 1]), dy = Double(gy[i] - gy[i - 1]), dz = Double(gz[i] - gz[i - 1])
                still = (dx * dx + dy * dy + dz * dz).squareRoot() < cut
            }
            prefix[i + 1] = prefix[i] + (still ? 1 : 0)
        }
        var flags = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let lo = max(0, i - half), hi = min(n, i + half + 1)
            flags[i] = Double(prefix[hi] - prefix[lo]) / Double(hi - lo) >= stillFraction
        }
        return (flags, prefix)
    }

    /// The 15-minute window rounds every run off: it only turns "sleep" ~3 minutes after the
    /// wrist went still and turns back ~3 minutes before it moved again. Walk each edge back out
    /// to where the stillness really starts and stops (the adjoining half-minute must itself be
    /// ≥ 80 % still), by at most 8 minutes and never across a recording gap.
    static func refineEdges(_ periods: [Period], gTs: [Int], stillPrefix: [Int32]) -> [Period] {
        let n = gTs.count
        guard n >= 2, stillPrefix.count == n + 1 else { return periods }
        let span = edgeProbeSamples
        var out = periods
        for k in out.indices where out[k].sleep {
            var a = TimeIndex.lowerBound(gTs, out[k].start) { $0 }
            var b = TimeIndex.lowerBound(gTs, out[k].end + 1) { $0 } - 1
            guard a < n, b >= a else { continue }
            let startTs = gTs[a], endTs = gTs[b]
            let floorTs = k > 0 && out[k - 1].sleep ? out[k - 1].end + 1 : Int.min
            while a > 0, startTs - gTs[a - 1] <= edgeMaxExtendSec, gTs[a] - gTs[a - 1] <= edgeMaxStepSec,
                  gTs[a - 1] >= floorTs {
                let lo = max(0, a - span)
                guard Double(stillPrefix[a] - stillPrefix[lo]) >= edgeStillFraction * Double(a - lo) else { break }
                a -= 1
            }
            let ceilTs = k + 1 < out.count && out[k + 1].sleep ? out[k + 1].start - 1 : Int.max
            while b + 1 < n, gTs[b + 1] - endTs <= edgeMaxExtendSec, gTs[b + 1] - gTs[b] <= edgeMaxStepSec,
                  gTs[b + 1] <= ceilTs {
                let hi = min(n, b + 1 + span)
                guard Double(stillPrefix[hi] - stillPrefix[b + 1]) >= edgeStillFraction * Double(hi - b - 1) else { break }
                b += 1
            }
            out[k].start = gTs[a]
            out[k].end = gTs[b]
        }
        return out
    }

    /// Mean heart rate across `[a, b]` within the sleep band (a short gap only).
    static func hrSleepBandAcross(_ a: Int, _ b: Int, hr: HRIndex, baseline: Double?) -> Bool {
        guard let baseline, b > a, b - a <= bridgeGapMin * 60, let s = hr.stats(a, b) else { return false }
        return s.mean <= baseline * hrSleepBaselineMult
    }

    static func buildRuns(gTs: [Int], flags: [Bool], sparse: Bool, hr: HRIndex, baseline: Double?) -> [Period] {
        let n = gTs.count
        guard n > 0 else { return [] }
        let maxGapS = maxGapMin * 60
        var periods: [Period] = []
        var runStart = 0
        for i in 1...n {
            var close = i == n
            if !close {
                let classChanged = flags[i] != flags[runStart]
                var gapExceeded = gTs[i] - gTs[i - 1] > maxGapS
                if sparse, gapExceeded, !classChanged, flags[runStart],
                   hrSleepBandAcross(gTs[i - 1], gTs[i], hr: hr, baseline: baseline) {
                    gapExceeded = false
                }
                close = classChanged || gapExceeded
            }
            if close {
                periods.append(Period(sleep: flags[runStart], start: gTs[runStart], end: gTs[i - 1]))
                runStart = i
            }
        }
        return periods
    }

    /// Absorb runs shorter than `mergeMin` into their neighbours (never across a recording gap).
    static func mergePeriods(_ periods: [Period], mergeMinutes: Int = mergeMin) -> [Period] {
        let threshold = mergeMinutes * 60
        let maxObservedGap = maxGapMin * 60
        var pending = periods
        var merged: [Period] = []
        var i = 0
        while i < pending.count {
            let cur = pending[i]
            if cur.span >= threshold { merged.append(cur); i += 1; continue }
            let hasPrev = !merged.isEmpty && cur.start - merged[merged.count - 1].end <= maxObservedGap
            let hasNext = i + 1 < pending.count && pending[i + 1].start - cur.end <= maxObservedGap
            if hasPrev && hasNext && merged[merged.count - 1].sleep == pending[i + 1].sleep {
                let prev = merged.removeLast()
                merged.append(Period(sleep: prev.sleep, start: prev.start, end: pending[i + 1].end))
                i += 2
            } else if hasNext {
                pending[i + 1] = Period(sleep: pending[i + 1].sleep, start: cur.start, end: pending[i + 1].end)
                i += 1
            } else if hasPrev {
                let prev = merged.removeLast()
                merged.append(Period(sleep: prev.sleep, start: prev.start, end: cur.end))
                i += 1
            } else {
                merged.append(cur)
                i += 1
            }
        }
        return merged
    }

    /// Re-stitch sleep runs split by a recording gap or by one short active run, when the heart
    /// rate stayed in the sleep band across the split. Enabled for a pair when the motion stream
    /// is sparse, or when one side is too short to survive the minimum-duration gate on its own
    /// (a night fragmented into pieces would otherwise vanish entirely).
    static func bridgeFragments(_ periods: [Period], sparse: Bool, hr: HRIndex, baseline: Double?) -> [Period] {
        guard !periods.isEmpty else { return periods }
        let gapMax = bridgeGapMin * 60
        let minSleepS = minSleepMin * 60
        var out: [Period] = []
        func canBridge(_ left: Period, _ right: Period, activeS: Int) -> Bool {
            guard sparse || left.span < minSleepS || right.span < minSleepS else { return false }
            let gap = right.start - left.end
            guard gap >= 0, gap <= gapMax else { return false }
            let inBand = hrSleepBandAcross(left.end, right.start, hr: hr, baseline: baseline)
            let cap = (inBand ? max(bridgeActiveMaxMin, bridgeActiveMaxInBandMin) : bridgeActiveMaxMin) * 60
            return activeS <= cap && inBand
        }
        for p in periods {
            if p.sleep {
                if let last = out.last, last.sleep, canBridge(last, p, activeS: 0) {
                    out[out.count - 1] = Period(sleep: true, start: last.start, end: p.end)
                    continue
                }
                if out.count >= 2, let last = out.last, !last.sleep, out[out.count - 2].sleep {
                    let prev = out[out.count - 2]
                    if canBridge(prev, p, activeS: last.span) {
                        out.removeLast()
                        out[out.count - 1] = Period(sleep: true, start: prev.start, end: p.end)
                        continue
                    }
                }
            }
            out.append(p)
        }
        return out
    }

    // MARK: - Gates

    static func secOfDay(_ local: Int) -> Int { ((local % 86400) + 86400) % 86400 }

    static func isDaytimeCentre(_ p: Period, tz: (Int) -> Int) -> Bool {
        let centre = p.start + p.span / 2
        let hour = secOfDay(centre + tz(centre)) / 3600
        return hour >= daytimeBandStartHour && hour < daytimeBandEndHour
    }

    static func isOvernightOnset(_ start: Int, tz: (Int) -> Int) -> Bool {
        let hour = secOfDay(start + tz(start)) / 3600
        return !(hour >= daytimeBandStartHour && hour < daytimeBandEndHour)
    }

    /// The wrist did not change posture during ≥ 90 % of the run's minutes.
    static func deeplyQuiescent(_ p: Period, gTs: [Int], gx: [Float], gy: [Float], gz: [Float]) -> Bool {
        let lo = TimeIndex.lowerBound(gTs, p.start) { $0 }
        let hi = TimeIndex.lowerBound(gTs, p.end) { $0 }
        guard hi > lo else { return false }
        var judged = 0, stable = 0
        var i = lo
        while i < hi {
            let minute = gTs[i] / 60
            var j = i
            var sx = 0.0, sy = 0.0, sz = 0.0
            while j < hi && gTs[j] / 60 == minute {
                sx += Double(gx[j]); sy += Double(gy[j]); sz += Double(gz[j]); j += 1
            }
            let n = j - i
            if n >= 2 {
                let mx = sx / Double(n), my = sy / Double(n), mz = sz / Double(n)
                var ss = 0.0
                for k in i..<j {
                    let dx = Double(gx[k]) - mx, dy = Double(gy[k]) - my, dz = Double(gz[k]) - mz
                    ss += dx * dx + dy * dy + dz * dz
                }
                judged += 1
                if ss / Double(n) < quiescentPostureVarG2 { stable += 1 }
            }
            i = j
        }
        return judged >= quiescentMinStableMinutes && Double(stable) / Double(judged) >= quiescentStableFrac
    }

    static func confirmWithHR(_ p: Period, hr: HRIndex, baseline: Double?, quiescent: @autoclosure () -> Bool) -> Bool {
        guard let baseline, let s = hr.stats(p.start, p.end), s.count >= hrRefineMinSamples else { return true }
        let mult = quiescent() ? quiescentHRSleepMult : hrSleepBaselineMult
        return s.median <= baseline * mult
    }

    /// Off-wrist coverage of a run: long heart-rate gaps (the strap reports no HR off the skin)
    /// united with the strap's own wrist-off intervals.
    static func offWristFraction(_ p: Period, hr: HRIndex, wristOff: [(start: Int, end: Int)]) -> Double {
        let dur = p.span
        guard dur > 0 else { return 0 }
        var spans: [(Int, Int)] = []
        if !hr.isEmpty {
            let streamSpan = hr.ts[hr.count - 1] - hr.ts[0]
            let dense = !(streamSpan >= hrDenseSpacingS && hr.count < streamSpan / hrDenseSpacingS)
            if dense {
                let gapS = offWristHRGapMin * 60
                let r = hr.bounds(p.start, p.end)
                if r.isEmpty {
                    if dur >= gapS { spans.append((p.start, p.end)) }
                } else {
                    if hr.ts[r.lowerBound] - p.start >= gapS { spans.append((p.start, hr.ts[r.lowerBound])) }
                    var i = r.lowerBound + 1
                    while i < r.upperBound {
                        if hr.ts[i] - hr.ts[i - 1] >= gapS { spans.append((hr.ts[i - 1], hr.ts[i])) }
                        i += 1
                    }
                    if p.end - hr.ts[r.upperBound - 1] >= gapS { spans.append((hr.ts[r.upperBound - 1], p.end)) }
                }
            }
        }
        for w in wristOff {
            let s = max(w.start, p.start), e = min(w.end, p.end)
            if e > s { spans.append((s, e)) }
        }
        guard !spans.isEmpty else { return 0 }
        spans.sort { $0.0 < $1.0 }
        var covered = 0
        var cs = spans[0].0, ce = spans[0].1
        for sp in spans.dropFirst() {
            if sp.0 <= ce { ce = max(ce, sp.1) } else { covered += ce - cs; cs = sp.0; ce = sp.1 }
        }
        covered += ce - cs
        return Double(covered) / Double(dur)
    }

    static func bandAsleepFraction(_ a: Int, _ b: Int, bandTs: [Int], bandState: [Int8]) -> Double? {
        let lo = TimeIndex.lowerBound(bandTs, a) { $0 }
        let hi = TimeIndex.lowerBound(bandTs, b + 1) { $0 }
        guard hi > lo else { return nil }
        var asleep = 0
        for i in lo..<hi where bandState[i] == bandSleep { asleep += 1 }
        return Double(asleep) / Double(hi - lo)
    }

    /// Is this still stretch sleep, or quiet wakefulness (a film, a desk, reading in bed)?
    /// Stillness with a heart rate "not above the day's median" is both. Two independent
    /// witnesses decide: the strap's own state (does IT call most of the stretch asleep?) and
    /// the heart rate against the sleeping trough of the surrounding hours (quiet wakefulness
    /// sits well above it). With no strap state (WHOOP 4.0, live-only data) the heart rate
    /// decides alone, more strictly.
    static func hasSleepEvidence(_ p: Period, hr: HRIndex, bandTs: [Int], bandState: [Int8]) -> Bool {
        guard let s = hr.stats(p.start, p.end), s.count >= hrRefineMinSamples,
              let trough = hr.percentile(hrOnlyAnchorPercentile, from: p.start - evidenceNeighbourhoodS,
                                         to: p.end + evidenceNeighbourhoodS), trough > 0 else { return true }
        let ratio = s.median / trough
        let lo = TimeIndex.lowerBound(bandTs, p.start) { $0 }
        let hi = TimeIndex.lowerBound(bandTs, p.end + 1) { $0 }
        if Double(hi - lo) >= evidenceMinBandCoverage * Double(max(1, p.span)) {
            var asleep = 0
            for i in lo..<hi where bandState[i] == bandSleep { asleep += 1 }
            let frac = Double(asleep) / Double(hi - lo)
            if frac >= evidenceBandAccept { return ratio <= evidenceHRRatioWithBand }
            if frac < evidenceBandReject { return false }
            return ratio <= evidenceHRRatioWeakBand
        }
        return ratio <= (p.span >= evidenceLongRunS ? evidenceHRRatioNoBandLong : evidenceHRRatioNoBand)
    }

    static func acceptRuns(_ periods: [Period], hr: HRIndex, baseline: Double?, tz: (Int) -> Int,
                           wristOff: [(start: Int, end: Int)],
                           gTs: [Int], gx: [Float], gy: [Float], gz: [Float],
                           bandTs: [Int], bandState: [Int8]) -> [SleepRun] {
        let minSleepS = minSleepMin * 60
        let continuationGapS = nightContinuationGapMin * 60
        var chainPrevEnd: Int?
        var chainFromOvernight = false
        var nightTailAccepted = false
        var runs: [SleepRun] = []
        for p in periods where p.sleep {
            let continuesChain = chainPrevEnd.map { p.start - $0 <= continuationGapS } ?? false
            // A re-onset right after the overnight block is the night going on, not a nap: it
            // skips the daytime guard, and the first SHORT one per night is exempt from the
            // 60-minute floor.
            let nightContinuation = continuesChain && chainFromOvernight
            let isNightTail = nightContinuation && !nightTailAccepted
            if p.span <= minSleepS && !isNightTail { continue }
            if p.span > maxMainSleepSpanS { continue }
            if !confirmWithHR(p, hr: hr, baseline: baseline,
                              quiescent: deeplyQuiescent(p, gTs: gTs, gx: gx, gy: gy, gz: gz)) { continue }
            if offWristFraction(p, hr: hr, wristOff: wristOff) >= maxOffWristSleepFraction { continue }
            if !hasSleepEvidence(p, hr: hr, bandTs: bandTs, bandState: bandState) { continue }

            if isDaytimeCentre(p, tz: tz) && !nightContinuation {
                let resting = hr.lowestBinMean(p.start, p.end)
                func passesDaytime() -> Bool {
                    guard p.span >= daytimeMinSleepMin * 60, let baseline, let resting else { return false }
                    return resting.rounded() <= baseline * daytimeRestingHRMult
                }
                var ok = passesDaytime()
                if ok, chainFromOvernight, let wakeEnd = chainPrevEnd, p.start >= wakeEnd,
                   p.start - wakeEnd <= morningStillnessWindowMin * 60 {
                    // Stillness shortly after the morning wake (breakfast, commute, desk): a real
                    // second sleep needs the strap's own verdict or a deeper heart-rate dip.
                    let bandOK = (bandAsleepFraction(p.start, p.end, bandTs: bandTs, bandState: bandState) ?? 0)
                        >= morningReonsetBandAsleepFrac
                    let deepDip = (baseline != nil && resting != nil)
                        && resting!.rounded() <= baseline! * morningReonsetRestingHRMult
                    ok = bandOK || deepDip
                }
                if !ok { continue }
            }

            runs.append(SleepRun(start: p.start, end: p.end + 1))
            if !continuesChain {
                chainFromOvernight = isOvernightOnset(p.start, tz: tz)
                nightTailAccepted = false
            } else if !chainFromOvernight && isOvernightOnset(p.start, tz: tz) {
                chainFromOvernight = true
            } else if isNightTail && p.span <= minSleepS {
                nightTailAccepted = true
            }
            chainPrevEnd = p.end
        }
        return runs
    }

    // MARK: - Heart-rate-only spine

    /// Heart-rate samples lying in stretches with no motion data within ±10 min.
    static func hrOutsideGravity(_ hr: HRIndex, gTs: [Int]) -> HRIndex {
        guard !gTs.isEmpty else { return hr }
        var out = HRIndex()
        var g = 0
        for i in 0..<hr.count {
            let t = hr.ts[i]
            while g + 1 < gTs.count && gTs[g + 1] <= t { g += 1 }
            var nearest = abs(gTs[g] - t)
            if g + 1 < gTs.count { nearest = min(nearest, abs(gTs[g + 1] - t)) }
            if nearest > hrOnlyHoleS { out.ts.append(t); out.bpm.append(hr.bpm[i]) }
        }
        return out
    }

    /// Sleep/active runs from per-minute median heart rate against a low-percentile anchor.
    /// A minute is a candidate up to `hrOnlyExtendedMult` × the anchor; a run is kept only when
    /// enough of it sits in the trough itself (≤ `hrOnlyBandMult` × the anchor) — so a quiet
    /// evening above the sleeping level never qualifies, while REM and late-night cycles do
    /// not shred a real night.
    static func hrOnlyPeriods(_ hr: HRIndex, baseline: Double) -> [Period] {
        guard baseline > 0, !hr.isEmpty else { return [] }
        var keys: [Int] = [], flags: [Bool] = [], core: [Bool] = [], ends: [Int] = []
        var i = 0
        while i < hr.count {
            let k = hr.ts[i] / hrOnlyEpochS
            var hist = [Int](repeating: 0, count: 256)
            var j = i
            while j < hr.count && hr.ts[j] / hrOnlyEpochS == k { hist[Int(hr.bpm[j])] += 1; j += 1 }
            let med = HRIndex.percentile(hist, total: j - i, p: 0.5, interpolate: true)
            keys.append(k)
            flags.append(med <= baseline * hrOnlyExtendedMult)
            core.append(med <= baseline * hrOnlyBandMult)
            ends.append(hr.ts[j - 1])
            i = j
        }
        let maxGapS = maxGapMin * 60
        var periods: [Period] = []
        var runStart = 0
        for i in 1...keys.count {
            let close = i == keys.count || flags[i] != flags[runStart]
                || (keys[i] - keys[i - 1]) * hrOnlyEpochS > maxGapS
            if close {
                periods.append(Period(sleep: flags[runStart], start: keys[runStart] * hrOnlyEpochS, end: ends[i - 1]))
                runStart = i
            }
        }
        periods = mergePeriods(periods)
        // Keep a sleep run only when it is anchored in the trough.
        return periods.map { p in
            guard p.sleep else { return p }
            let lo = TimeIndex.lowerBound(keys, p.start / hrOnlyEpochS) { $0 }
            let hi = TimeIndex.lowerBound(keys, p.end / hrOnlyEpochS + 1) { $0 }
            guard hi > lo else { return Period(sleep: false, start: p.start, end: p.end) }
            var n = 0
            for k in lo..<hi where core[k] { n += 1 }
            let anchored = Double(n) >= hrOnlyMinCoreFraction * Double(hi - lo)
            return Period(sleep: anchored, start: p.start, end: p.end)
        }
    }

    // MARK: - Nights

    /// Chain runs into nights: a gap under an hour (or ≤ 90 min when the chain is overnight) is
    /// an awakening inside one night.
    static func groupNights(_ runs: [SleepRun], tz: (Int) -> Int) -> [NightGroup] {
        let sorted = runs.sorted { $0.start < $1.start }
        var out: [NightGroup] = []
        for r in sorted {
            if var last = out.last {
                let gap = r.start - last.end
                let chain: Bool
                if gap < 0 { chain = true }
                else if gap < groupGapMin * 60 { chain = true }
                else {
                    chain = gap <= nightContinuationGapMin * 60
                        && (isOvernightOnset(r.start, tz: tz) || last.runs.contains { isOvernightOnset($0.start, tz: tz) })
                }
                if chain {
                    last.runs.append(r)
                    out[out.count - 1] = last
                    continue
                }
            }
            out.append(NightGroup(runs: [r]))
        }
        return out
    }

    static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let raw = abs(a - b) % 86400
        return min(raw, 86400 - raw)
    }

    static func alignmentBonus(_ g: NightGroup, target: Int, tz: (Int) -> Int) -> Double {
        let mid = g.midsleep
        let dist = circularDistance(secOfDay(mid + tz(mid)), target)
        if dist <= alignmentFullWindowSec { return alignmentBonusMin }
        if dist >= alignmentZeroSec { return 0 }
        return alignmentBonusMin * Double(alignmentZeroSec - dist) / Double(alignmentZeroSec - alignmentFullWindowSec)
    }

    /// The main night among `groups`: most minutes asleep, plus up to 90 min of bonus for sitting
    /// near the wearer's usual mid-sleep (03:30 until 14 nights are known).
    static func pickMain(_ groups: [NightGroup], habitualMidsleepSec: Int?, tz: (Int) -> Int) -> Int? {
        guard !groups.isEmpty else { return nil }
        let target = habitualMidsleepSec ?? coldStartMidsleepSec
        var best = 0
        var bestScore = groups[0].asleepMin + alignmentBonus(groups[0], target: target, tz: tz)
        for i in 1..<groups.count {
            let score = groups[i].asleepMin + alignmentBonus(groups[i], target: target, tz: tz)
            if score > bestScore || (score == bestScore && groups[i].start < groups[best].start) {
                best = i
                bestScore = score
            }
        }
        return best
    }

    /// Usual mid-sleep (local second of day) from past nights, or nil below 14 nights.
    static func habitualMidsleep(_ nights: [(start: Int, end: Int)], tz: (Int) -> Int) -> Int? {
        guard nights.count >= habitualMinDays else { return nil }
        var sumSin = 0.0, sumCos = 0.0
        let k = 2 * Double.pi / 86400
        for n in nights {
            let mid = n.start + (n.end - n.start) / 2
            let a = Double(secOfDay(mid + tz(mid))) * k
            sumSin += sin(a); sumCos += cos(a)
        }
        let resultant = (sumSin * sumSin + sumCos * sumCos).squareRoot() / Double(nights.count)
        guard resultant > 1e-9 else { return nil }
        var ang = atan2(sumSin, sumCos)
        if ang < 0 { ang += 2 * Double.pi }
        return secOfDay(Int((ang / k).rounded()))
    }

    // MARK: - Strap envelope

    /// End of the night according to the strap's own state: when the strap reports "asleep" for
    /// the last time and then stays awake (continuously observed, no re-settling) for at least
    /// 10 minutes, the remainder was a lie-in. Never "first up": mid-night up runs that return to
    /// sleep are normal. Returns the new exclusive end, or nil when the rule does not apply.
    static func bandTrimmedEnd(start: Int, end: Int, samples: ArraySlice<HistorySample>,
                               minNight: Int = minNightSec) -> Int? {
        guard end > start else { return nil }
        let slice = TimeIndex.slice(samples, from: start, to: end)
        var known = 0
        var lastSleep: Int?
        for s in slice where s.sleepState >= 0 && s.sleepState <= 3 {
            known += 1
            if s.sleepState == bandSleep { lastSleep = s.ts }
        }
        guard let lastSleep, known * 100 >= (end - start) * minBandCoveragePct else { return nil }
        let newEnd = lastSleep + 1
        let tail = end - newEnd
        guard tail >= minBandTrimSec, newEnd - start >= minNight else { return nil }
        var tailKnown = 0, still = 0, maxGap = 0
        var prev = lastSleep
        for s in slice where s.ts >= newEnd && s.sleepState >= 0 && s.sleepState <= 3 {
            if s.sleepState == bandStill { still += 1 }
            tailKnown += 1
            maxGap = max(maxGap, s.ts - prev - 1)
            prev = s.ts
        }
        maxGap = max(maxGap, end - 1 - prev)
        guard tailKnown * 100 >= tail * minBandTailCoveragePct, maxGap <= maxBandTailGapSec,
              still <= maxBandTailStillSec else { return nil }
        return newEnd
    }

    /// Pair the strap's wrist-off / wrist-on events into off-wrist intervals.
    static func offWristIntervals(_ events: [StoredEvent], windowEnd: Int) -> [(start: Int, end: Int)] {
        let wear = events.filter { $0.id == EventID.wristOff || $0.id == EventID.wristOn }.sorted { $0.ts < $1.ts }
        var out: [(start: Int, end: Int)] = []
        var offStart: Int?
        for e in wear where e.ts <= windowEnd {
            if e.id == EventID.wristOff {
                if offStart == nil { offStart = e.ts }
            } else {
                if let s = offStart, e.ts > s { out.append((s, e.ts)) }
                offStart = nil
            }
        }
        if let s = offStart, windowEnd > s { out.append((s, windowEnd)) }
        return out
    }
}

/// Daytime naps: sustained wrist immobility (van Hees z-angle) outside the nights, backed by a
/// heart-rate dip against the wearer's own awake level — and by the strap's own "asleep" state
/// when it reports one. Stillness alone is also desk work, reading or a film.
/// Adapted from OpenStrap `detectNaps`.
enum NapDetector {
    static let minNapSec = 15 * 60
    static let maxNapSec = 6 * 3600
    static let bridgeSec = 5 * 60
    static let restingHRMult = 0.95
    static let minHRCoverage = 0.5
    static let minAccelCoverage = 0.5
    static let maxOffWristFraction = 0.5
    static let minAwakeHRSamples = 10 * 60
    static let angleThresholdDeg = 5.0
    static let sustainedSec = 5 * 60
    static let smoothSamples = 5
    static let maxCadenceSec = 5
    /// With the strap's envelope available, a nap needs this much "asleep" time in it.
    static let minBandSleepSec = 5 * 60
    static let minBandSleepFraction = 0.3

    struct Nap: Equatable {
        var start: Int
        var end: Int
        /// Still seconds inside the bout.
        var asleepSec: Int
    }

    /// - Parameter taken: `[start, end)` windows already attributed to a night or another sleep.
    static func detect(_ samples: ArraySlice<HistorySample>, taken: [(start: Int, end: Int)],
                       mainEnd: Int?, wristOff: [(start: Int, end: Int)] = []) -> [Nap] {
        var ts: [Int] = [], ang: [Double] = []
        ts.reserveCapacity(samples.count); ang.reserveCapacity(samples.count)
        var hr = SleepSpine.HRIndex()
        var bandTs: [Int] = [], bandState: [Int8] = []
        for s in samples {
            if s.hasGravity {
                let x = Double(s.gx), y = Double(s.gy), z = Double(s.gz)
                ts.append(s.ts)
                ang.append(atan2(z, (x * x + y * y).squareRoot()) * 180 / Double.pi)
            }
            if s.hr > 0 { hr.ts.append(s.ts); hr.bpm.append(s.hr) }
            if s.sleepState >= 0 { bandTs.append(s.ts); bandState.append(s.sleepState) }
        }
        if !SleepSpine.bandIsAlive(bandState) { bandTs = []; bandState = [] }
        let n = ts.count
        guard n >= minNapSec else { return [] }
        // 5-sample rolling median of the arm angle, then its change over 5 samples.
        var smooth = [Double](repeating: 0, count: n)
        var buf = [Double](repeating: 0, count: smoothSamples)
        for i in 0..<n {
            let lo = max(0, i - smoothSamples / 2), hi = min(n - 1, i + smoothSamples / 2)
            var c = 0
            for k in lo...hi { buf[c] = ang[k]; c += 1 }
            buf[0..<c].sort()
            smooth[i] = c % 2 == 1 ? buf[c / 2] : (buf[c / 2 - 1] + buf[c / 2]) / 2
        }
        func stillAt(_ k: Int) -> Bool {
            guard k > 0 else { return true }
            guard ts[k] - ts[k - 1] <= maxCadenceSec else { return false }
            let from = max(0, k - smoothSamples)
            guard ts[k] - ts[from] <= maxCadenceSec * smoothSamples else { return false }
            return abs(smooth[k] - smooth[from]) < angleThresholdDeg
        }
        var still = [Bool](repeating: false, count: n)
        for k in 0..<n { still[k] = stillAt(k) }
        // Runs of sustained stillness, bridged across brief arousals.
        var bouts: [(Int, Int)] = [] // sample index range [a, b)
        var i = 0
        while i < n {
            guard still[i] else { i += 1; continue }
            var j = i
            while j < n && still[j] { j += 1 }
            if ts[j - 1] + 1 - ts[i] >= sustainedSec {
                if let last = bouts.last, ts[i] - (ts[last.1 - 1] + 1) < bridgeSec {
                    bouts[bouts.count - 1].1 = j
                } else {
                    bouts.append((i, j))
                }
            }
            i = j
        }
        guard !bouts.isEmpty else { return [] }

        func overlapsTaken(_ a: Int, _ b: Int) -> Bool { taken.contains { $0.start < b && a < $0.end } }
        // Awake heart rate: everything outside the nights/sleeps already found.
        var awakeHist = [Int](repeating: 0, count: 256)
        var awakeN = 0
        var ti = 0
        let takenSorted = taken.sorted { $0.start < $1.start }
        for k in 0..<hr.count {
            let t = hr.ts[k]
            while ti < takenSorted.count && takenSorted[ti].end <= t { ti += 1 }
            if ti < takenSorted.count && t >= takenSorted[ti].start { continue }
            awakeHist[Int(hr.bpm[k])] += 1
            awakeN += 1
        }
        guard awakeN >= minAwakeHRSamples else { return [] }

        var naps: [Nap] = []
        for (a, b) in bouts {
            // A bout still running at the last sample has no knowable end yet.
            if b >= n && n > 0 && ts[n - 1] - ts[b - 1] < 60 && (samples.last?.ts ?? 0) - ts[b - 1] < sustainedSec { continue }
            let start = ts[a], end = ts[b - 1] + 1
            let tib = end - start
            guard tib >= minNapSec, tib <= maxNapSec, !overlapsTaken(start, end) else { continue }
            guard Double(b - a) / Double(tib) >= minAccelCoverage else { continue }
            let p = SleepSpine.Period(sleep: true, start: start, end: end)
            guard SleepSpine.offWristFraction(p, hr: hr, wristOff: wristOff) < maxOffWristFraction else { continue }
            guard let s = hr.stats(start, end - 1), Double(s.count) / Double(tib) >= minHRCoverage else { continue }
            // Baseline: awake heart rate outside this bout (it is outside by construction).
            let baseline = SleepSpine.HRIndex.percentile(awakeHist, total: awakeN, p: 0.5, interpolate: true)
            guard baseline > 0, s.median <= baseline * restingHRMult else { continue }
            // A short still block right after the night is the night going on, not a nap.
            if let mainEnd, tib <= SleepSpine.minSleepMin * 60, start >= mainEnd,
               start - mainEnd <= SleepSpine.nightContinuationGapMin * 60 { continue }
            // The strap's own verdict, when it has one for this stretch.
            let lo = TimeIndex.lowerBound(bandTs, start) { $0 }
            let hi = TimeIndex.lowerBound(bandTs, end) { $0 }
            if hi - lo >= tib / 2 {
                var asleep = 0
                for k in lo..<hi where bandState[k] == SleepSpine.bandSleep { asleep += 1 }
                if asleep < minBandSleepSec || Double(asleep) < minBandSleepFraction * Double(tib) { continue }
            }
            var stillN = 0
            for k in a..<b where still[k] { stillN += 1 }
            naps.append(Nap(start: start, end: end, asleepSec: min(tib, stillN)))
        }
        return naps
    }
}
