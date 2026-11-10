import Foundation

/// Everything the engine needs to compute one day.
struct DayInputs {
    var date: String
    /// ts-sorted samples covering at least [day start − 12 h, next day start + 12 h) (clipped to now).
    var samples: [HistorySample]
    var profile: UserProfile
    /// Previously computed days, ascending, all strictly before `date`.
    var history: [DayMetrics]
    /// User-created activities (manual / live) that may overlap the day.
    var userActivities: [ActivityRecord] = []
    var now: Int = Int(Date().timeIntervalSince1970)
    /// Strap events (wrist on / off) over the same window.
    var events: [StoredEvent] = []
    /// Personal calibration learned from the wearer's WHOOP export (nil = built-in defaults).
    var calibration: Calibration?
    /// Sleep times set by the wearer for this day: they replace the detected night.
    var forcedSleep: (start: Int, end: Int)?
}

/// Computes a WHOOP-style day: the night that ended on `date` (sleep + recovery), then the
/// strain cycle that runs until the next night begins.
enum DayEngine {
    /// Seconds east of GMT in effect at a unix time, on the device's calendar.
    static func tzOffset(_ unix: Int) -> Int {
        DayKey.calendar.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    static func compute(_ inp: DayInputs) -> DayMetrics {
        var out = DayMetrics(date: inp.date)
        out.computedAt = inp.now
        guard let dayStart = DayKey.startUnix(inp.date),
              let nextStart = DayKey.startUnix(DayKey.adding(1, to: inp.date)) else { return out }
        let samples = inp.samples
        let from = dayStart - 12 * 3600
        let to = min(inp.now, nextStart + 12 * 3600)
        guard to > from, !samples.isEmpty else { return out }
        let window = TimeIndex.slice(samples, from: from, to: to)
        let series = MinuteSeries.build(Array(window), from: from, to: to)
        let profile = inp.profile
        let history = inp.history
        let cal = inp.calibration
        let tz: (Int) -> Int = tzOffset

        // ── Sleep detection ───────────────────────────────────────────────────────────
        let wristOff = SleepSpine.offWristIntervals(inp.events, windowEnd: to)
        let detected = SleepSpine.detect(window, tz: tz, wristOff: wristOff)
        let pastNights = history.suffix(60).compactMap { d in d.sleep.map { (start: $0.start, end: $0.end) } }
        // The wearer's usual night decides how long an awakening may last before the next sleep
        // is a new one; the steps walked and the effort made in between tell a night awakening
        // from a day that has started.
        let restGuess = Stats.median(history.suffix(14).compactMap(\.rhr)) ?? 60
        var maxGuess = profile.tanakaMaxHR
        if let o = profile.maxHROverride, o > 100 { maxGuess = Double(o) }
        let exerciseHR = restGuess + 0.5 * max(40, maxGuess - restGuess)
        let context = SleepSpine.NightContext(habit: NightHabit.learn(pastNights, tz: tz), tz: tz, activity: { a, b in
            let i = max(0, series.index(of: a)), j = min(series.count, series.index(of: b) + 1)
            guard j > i else { return .unknown }
            var steps = 0, observed = 0, counted = 0, hard = 0
            for k in i..<j {
                steps += series.stepInc[k]
                if series.present[k] >= 20 { observed += 1 }
                if series.stepN[k] >= 20 { counted += 1 }
                if let h = series.hr(k), h >= exerciseHR { hard += 1 }
            }
            // The steps are known only when the counter was there for most of the awakening
            // (the live stream carries none).
            let known = counted > 0 && counted * 2 >= observed
            return SleepSpine.gapActivity(steps: known ? steps : nil, exerciseMinutes: hard)
        })
        // Short sleeps the spine does not keep on its own (under an hour): each one either
        // continues a night (a return to sleep) or stands alone (a nap).
        let bouts = NapDetector.detect(window, taken: detected.runs.map { ($0.start, $0.end) }, wristOff: wristOff)
            .map { SleepRun(start: $0.start, end: $0.end, bout: true) }
        var groups = SleepSpine.assembleNights(runs: detected.runs, bouts: bouts, context) { bout, leading in
            SleepSpine.boutIsSleep(bout, leading: leading, hr: detected.hr, bandTs: detected.bandTs,
                                   bandState: detected.bandState)
        }
        var stagedRuns: [Int: [StageSegment]] = [:]
        for gi in groups.indices {
            let runs = groups[gi].runs
            let staged = SleepStager.stageNight(samples: samples, runs: runs.map { ($0.start, $0.end) },
                                                priors: cal?.stageShares)
            var asleep = 0
            for (k, r) in runs.enumerated() {
                stagedRuns[r.start] = staged[k]
                asleep += staged[k].reduce(0) { $0 + ($1.stage == .wake ? 0 : $1.duration) }
            }
            groups[gi].asleepMin = Double(asleep) / 60
        }
        // The nights that END on this local day.
        let todays = groups.indices.filter { groups[$0].end > dayStart && groups[$0].end <= nextStart }
        func canBeMain(_ g: NightGroup) -> Bool {
            g.asleepMin >= 120 || (g.asleepMin >= 60 && SleepSpine.isOvernightOnset(g.start, tz: tz))
        }
        let habitual = SleepSpine.habitualMidsleep(pastNights, tz: tz)
        let mainCandidates = todays.filter { canBeMain(groups[$0]) }
        var mainIdx = SleepSpine.pickMain(mainCandidates.map { groups[$0] }, habitualMidsleepSec: habitual, tz: tz)
            .map { mainCandidates[$0] }
        var forced = false
        if let f = inp.forcedSleep, f.end > f.start, f.end - f.start <= 20 * 3600 {
            // The wearer's own times: stage that window as it is and drop whatever was detected
            // inside it.
            let run = SleepRun(start: f.start, end: f.end)
            stagedRuns[f.start] = SleepStager.stage(samples: samples, start: f.start, end: f.end, priors: cal?.stageShares)
            groups.removeAll { $0.start < f.end && f.start < $0.end }
            groups.append(NightGroup(runs: [run]))
            groups.sort { $0.start < $1.start }
            mainIdx = groups.firstIndex { $0.start == f.start }
            forced = true
        }
        let todayIdx = forced ? groups.indices.filter { groups[$0].end > dayStart && groups[$0].end <= nextStart } : todays

        var sleep: SleepSession?
        if let mi = mainIdx {
            var g = groups[mi]
            // The strap's own envelope may end the night earlier (lie-in after the last sleep).
            if !forced, let trimmed = SleepSpine.bandTrimmedEnd(start: g.start, end: g.end, samples: window) {
                g.runs = g.runs.compactMap { r in
                    guard r.start < trimmed else { return nil }
                    var c = r
                    c.end = min(r.end, trimmed)
                    return c
                }
                for r in g.runs {
                    stagedRuns[r.start] = (stagedRuns[r.start] ?? []).compactMap { seg in
                        guard seg.start < r.end else { return nil }
                        var c = seg
                        c.end = min(seg.end, r.end)
                        return c
                    }
                }
            }
            var built = buildSession(g, staged: stagedRuns, window: window, series: series, nap: false)
            // Keep the night's values exactly as measured, then put them on WHOOP's scale when
            // nights measured by both are available (see `Calibration.fitOverlap`).
            out.hrvRaw = built.hrv
            out.rhrRaw = built.rhr
            out.respRaw = built.respRate
            if let k = cal?.hrvScale, let v = built.hrv { built.hrv = Stats.clamp(v * k, 5, 250) }
            if let o = cal?.rhrOffset, let v = built.rhr { built.rhr = v + o }
            if let o = cal?.respOffset, let v = built.respRate { built.respRate = v + o }
            built.hrv = built.hrv.map { $0.rounded() }
            built.rhr = built.rhr.map { $0.rounded() }
            built.respRate = built.respRate.map { ($0 * 10).rounded() / 10 }
            sleep = built
        }
        let mainStart = sleep?.start ?? dayStart
        let mainEnd = sleep?.end

        // Naps: the other sleeps ending today. A return to sleep during the night is not one —
        // it was attached to its night above.
        var naps: [SleepSession] = []
        for gi in todayIdx where gi != mainIdx {
            let g = groups[gi]
            guard g.asleepMin >= 15, g.end - g.start <= 6 * 3600 else { continue }
            naps.append(buildSession(g, staged: stagedRuns, window: window, series: series, nap: true))
        }
        naps.sort { $0.start < $1.start }
        out.sleep = sleep
        out.naps = naps

        // The next night (starts after today's main sleep, ends tomorrow): closes the cycle.
        let nextMain = groups.filter { g in
            g.end > nextStart && canBeMain(g) && g.start > (mainEnd ?? dayStart)
        }.min { $0.start < $1.start }

        // ── Sleep need / debt / consistency / performance ─────────────────────────────
        let prev = history.last { $0.date == DayKey.adding(-1, to: inp.date) }
        let baseNeed = cal?.need?.baseSec ?? profile.baselineSleepNeedHours * 3600
        let carry = cal?.debtCarry ?? SleepCoach.debtCarry
        func debt(after d: DayMetrics?) -> Double {
            guard let d, let need = d.sleepNeedSec, let s = d.sleep else { return 0 }
            return SleepCoach.nextDebtSec(previousNeedSec: need, creditedSleepSec: Double(s.asleepSec), carry: carry)
        }
        let debtIn = debt(after: prev)
        let prevNapSec = Double(prev?.naps.reduce(0) { $0 + $1.asleepSec } ?? 0)
        let need = SleepCoach.needSec(baselineSec: baseNeed, priorStrain: prev?.strain, debtSec: debtIn,
                                      napSec: prevNapSec, model: cal?.need)
        out.sleepDebtSec = debtIn
        if let s = sleep {
            out.sleepNeedSec = need
            let hours = SleepCoach.hoursVsNeed(asleepSec: s.asleepSec, needSec: need) ?? 0
            out.sleepHoursVsNeed = hours
            var nights: [(start: Int, end: Int)] = []
            let floor = DayKey.adding(-4, to: inp.date)
            for d in history.suffix(6) where d.date >= floor {
                if let p = d.sleep { nights.append((p.start, p.end)) }
            }
            nights.append((s.start, s.end))
            if var c = SleepCoach.consistency(nights, tz: tz) {
                if let m = cal?.consistency { c = Stats.clamp(m.apply(c), 0, 100) }
                out.sleepConsistency = c.rounded()
            }
            out.sleepPerformance = SleepCoach.performance(
                hoursVsNeed: hours, consistency: out.sleepConsistency, efficiency: s.efficiency * 100,
                highStressPct: s.highStressPct, weights: cal?.perfWeights ?? SleepCoach.PerformanceWeights()).rounded()
            out.hrv = s.hrv
            out.rhr = s.rhr
            out.respRate = s.respRate
            out.spo2 = s.spo2
            out.skinTemp = s.skinTemp
        }

        // ── Cycle window ──────────────────────────────────────────────────────────────
        let cycleStart = mainStart
        var cycleEnd = nextMain?.start ?? min(inp.now, nextStart)
        if nextMain == nil && inp.now >= nextStart + 12 * 3600 { cycleEnd = nextStart }
        cycleEnd = max(cycleEnd, cycleStart)
        out.cycleStart = cycleStart
        out.cycleEnd = cycleEnd

        // Seconds asleep (main night or naps) inside the cycle — the stages, not the windows: an
        // hour awake in the middle of the night is waking time for the effort and the calories
        // (an arousal under five minutes is not).
        var asleepSpans: [(start: Int, end: Int)] = []
        for session in [sleep].compactMap({ $0 }) + naps {
            for seg in session.stages where seg.stage != .wake {
                if let last = asleepSpans.last, seg.start >= last.end, seg.start - last.end < 300 {
                    asleepSpans[asleepSpans.count - 1].end = seg.end
                } else {
                    asleepSpans.append((seg.start, seg.end))
                }
            }
        }
        asleepSpans.sort { $0.start < $1.start }
        func isAsleep(_ unix: Int) -> Bool {
            var lo = 0, hi = asleepSpans.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if asleepSpans[mid].end <= unix { lo = mid + 1 } else { hi = mid }
            }
            return lo < asleepSpans.count && asleepSpans[lo].start <= unix
        }

        // ── Anchors: resting HR, max HR ───────────────────────────────────────────────
        let recentRHR = history.suffix(14).compactMap(\.rhr) + [sleep?.rhr].compactMap { $0 }
        let restHR = sleep?.rhr ?? Stats.median(recentRHR) ?? 60
        let observedPeaks = history.suffix(30).compactMap { $0.maxHR.map(Double.init) }
        var maxHR = profile.tanakaMaxHR
        if let o = profile.maxHROverride, o > 100 { maxHR = Double(o) }
        else if let p = observedPeaks.max(), observedPeaks.count >= 3 {
            let secondBest = observedPeaks.sorted(by: >).dropFirst().first ?? p
            maxHR = max(maxHR, min(secondBest, 215))
        }
        maxHR = max(maxHR, restHR + 40)
        out.restingHRUsed = restHR
        out.maxHRUsed = maxHR

        let i0 = max(0, series.index(of: cycleStart)), i1 = min(series.count, series.index(of: cycleEnd))
        var awakeMinuteHR: [Double] = []
        var wornMinutes = 0, dataMinutes = 0
        if i1 > i0 {
            for i in i0..<i1 {
                if series.worn(i) { wornMinutes += 1 }
                if series.present[i] >= 20 { dataMinutes += 1 }
                if let h = series.hr(i), !isAsleep(series.unix(i)) { awakeMinuteHR.append(h) }
            }
        }
        out.wornMinutes = wornMinutes
        out.dataMinutes = dataMinutes
        out.cycleMinutes = max(0, (cycleEnd - cycleStart) / 60)
        out.quietHRR = Strain.dailyQuietHRR(minuteHR: awakeMinuteHR, rest: restHR, maxHR: maxHR)

        // ── Strain, zones, calories, steps over the cycle ─────────────────────────────
        let denominator = cal?.strainDenominator ?? Strain.defaultDenominator
        let kcalScale = cal?.kcalActiveScale ?? 1
        let cycleSlice = TimeIndex.slice(window, from: cycleStart, to: cycleEnd)
        var acc = Strain.Accumulator(rest: restHR, maxHR: maxHR, denominator: denominator)
        var curve: [Double] = []
        var zones = Array(repeating: 0, count: 6)
        var nextCurveAt = cycleStart + 900
        var prevTs: Int?
        for s in cycleSlice {
            while s.ts >= nextCurveAt {
                curve.append((acc.strain * 10).rounded() / 10)
                nextCurveAt += 900
            }
            guard s.hr > 0 else { prevTs = s.ts; continue }
            // A reading stands for the time since the previous one (1 s on history, capped on gaps).
            let dt = Double(min(max(1, s.ts - (prevTs ?? s.ts - 1)), 120))
            prevTs = s.ts
            if isAsleep(s.ts) { continue }
            acc.add(Double(s.hr), weight: dt / 60)
            zones[Strain.zone(Double(s.hr), rest: restHR, maxHR: maxHR)] += Int(dt)
        }
        curve.append((acc.strain * 10).rounded() / 10)

        var kcal = 0.0, active = 0.0, steps = 0
        var hrSum = 0.0, hrN = 0
        if i1 > i0 {
            for i in i0..<i1 {
                let asleep = isAsleep(series.unix(i))
                let h = series.hr(i)
                if let h { hrSum += h; hrN += 1 }
                let k = Strain.kcalForMinute(hr: h, asleep: asleep, rest: restHR, maxHR: maxHR, profile: profile,
                                             activeScale: kcalScale)
                kcal += k.total
                active += k.active
                steps += series.stepInc[i]
            }
        }
        if wornMinutes >= 10 {
            out.strain = (acc.strain * 10).rounded() / 10
            out.strainCurve = curve
            out.calories = kcal.rounded()
            out.activeCalories = active.rounded()
            out.avgHR = hrN > 0 ? (hrSum / Double(hrN)).rounded() : nil
            out.maxHR = sustainedPeak(cycleSlice)
            out.zoneSeconds = zones
            let hasStepCounter = cycleSlice.contains { $0.stepCounter >= 0 }
            out.steps = hasStepCounter ? steps : nil
        } else if cycleEnd > cycleStart {
            // Not enough wear for a strain: still show calories as basal estimate for the elapsed time.
            out.calories = (profile.bmr / 86400 * Double(cycleEnd - cycleStart)).rounded()
        }

        // ── Activities ────────────────────────────────────────────────────────────────
        var activities: [ActivityRecord] = []
        let users = inp.userActivities.filter { $0.end > cycleStart && $0.start < max(cycleEnd, $0.start + 1) && $0.start < nextStart + 12 * 3600 }
        for a in users {
            // WHOOP-imported workouts keep WHOOP's own strain/HR/zones.
            activities.append(a.source == .imported ? a
                              : scoreActivity(a, samples: samples, rest: restHR, maxHR: maxHR, profile: profile, cal: cal))
        }
        if i1 > i0 {
            let minuteHR: [Double?] = (i0..<i1).map { series.hr($0) }
            let bouts = ActivityDetector.detect(hr: minuteHR, start: series.unix(i0), rest: restHR, maxHR: maxHR,
                                                sleeping: { isAsleep(series.unix(i0 + $0)) })
            for b in bouts {
                let overlapsUser = users.contains { u in
                    let ov = min(u.end, b.end) - max(u.start, b.start)
                    return Double(ov) > 0.3 * Double(b.end - b.start)
                }
                if overlapsUser { continue }
                let sport = guessSport(TimeIndex.slice(samples, from: b.start, to: b.end))
                let rec = ActivityRecord(id: "auto-\(b.start)", sport: sport, start: b.start, end: b.end, source: .auto)
                activities.append(scoreActivity(rec, samples: samples, rest: restHR, maxHR: maxHR, profile: profile, cal: cal))
            }
        }
        out.activities = activities.sorted { $0.start < $1.start }

        // ── Recovery ──────────────────────────────────────────────────────────────────
        let skinHist = history.suffix(14).compactMap(\.skinTemp)
        if let t = sleep?.skinTemp, skinHist.count >= 3, let m = Stats.median(skinHist) {
            out.skinTempDev = ((t - m) * 10).rounded() / 10
        }
        if let hrv = sleep?.hrv {
            let b = Recovery.baselines(history: history)
            let inputs = Recovery.Inputs(hrv: hrv, rhr: sleep?.rhr, resp: sleep?.respRate,
                                         sleepPerformance: out.sleepPerformance, skinTempDev: out.skinTempDev)
            if let model = cal?.recovery, let score = Recovery.score(inputs, b, model: model) {
                out.recovery = score.rounded()
                out.recoveryCalibrated = true
            } else if let score = Recovery.score(inputs, b) {
                out.recovery = score.rounded()
            } else {
                out.calibrationNights = min(Recovery.calibrationNights - 1, history.compactMap(\.hrv).count) + 1
            }
        }

        // ── Tonight's need, fitness, trace ────────────────────────────────────────────
        var debtTonight = debtIn
        if let s = sleep {
            debtTonight = SleepCoach.nextDebtSec(previousNeedSec: need, creditedSleepSec: Double(s.asleepSec), carry: carry)
        }
        let napSec = Double(naps.reduce(0) { $0 + $1.asleepSec })
        out.tonightNeedSec = SleepCoach.needSec(baselineSec: baseNeed, priorStrain: out.strain, debtSec: debtTonight,
                                                napSec: napSec, model: cal?.need)
        let rhrForFitness = Stats.median(recentRHR)
        if let r = rhrForFitness { out.vo2max = Fitness.vo2max(maxHR: maxHR, restingHR: r).map { ($0 * 10).rounded() / 10 } }

        if cycleEnd > cycleStart {
            var trace: [Int] = []
            var t = cycleStart
            while t < cycleEnd {
                let a = series.index(of: t), b = min(series.index(of: t + 300), series.count)
                var sum = 0.0, n = 0
                if a >= 0 && b > a { for i in a..<b where series.hrN[i] > 0 { sum += series.hrSum[i]; n += series.hrN[i] } }
                trace.append(n > 0 ? Int((sum / Double(n)).rounded()) : 0)
                t += 300
            }
            out.hrTrace = trace
            out.hrTraceStart = cycleStart
        }
        return out
    }

    // MARK: - Sleep summary

    /// Turn a night group (its runs already staged) into a session with WHOOP's sleep figures.
    static func buildSession(_ g: NightGroup, staged: [Int: [StageSegment]], window: ArraySlice<HistorySample>,
                             series: MinuteSeries, nap: Bool) -> SleepSession {
        var s = SleepSession(start: g.start, end: g.end, isNap: nap)
        s.bandDetected = !g.hrOnly
        // Stages: each run's hypnogram; the time between two runs is an awakening when the strap
        // was observed there, and unobserved otherwise.
        var stages: [StageSegment] = []
        var prevEnd: Int?
        for r in g.runs {
            if let pe = prevEnd, r.start > pe {
                let a = max(0, series.index(of: pe)), b = min(series.count, series.index(of: r.start))
                let observed = b > a ? (a..<b).filter { series.worn($0) }.count : 0
                if b > a && observed * 2 >= b - a {
                    stages.append(StageSegment(start: pe, end: r.start, stage: .wake))
                }
            }
            stages.append(contentsOf: staged[r.start] ?? [])
            prevEnd = r.end
        }
        // Merge touching segments of the same stage.
        var merged: [StageSegment] = []
        for seg in stages where seg.duration > 0 {
            if let last = merged.last, last.stage == seg.stage, last.end == seg.start {
                merged[merged.count - 1].end = seg.end
            } else {
                merged.append(seg)
            }
        }
        s.stages = merged
        for seg in merged {
            switch seg.stage {
            case .wake: s.awakeSec += seg.duration
            case .light: s.lightSec += seg.duration
            case .deep: s.deepSec += seg.duration
            case .rem: s.remSec += seg.duration
            }
        }
        s.unobservedSec = max(0, s.inBedSec - s.awakeSec - s.asleepSec)

        // Latency: time to the first sustained (≥ 5 min) sleep.
        var run = 0
        var onset = g.start
        for seg in merged {
            if seg.stage == .wake { run = 0; continue }
            run += seg.duration
            if run >= 300 { onset = seg.end - run; break }
        }
        s.latencySec = max(0, onset - g.start)
        // Disturbances: wake bouts ≥ 1 min after onset, before the final wake.
        let lastSleepEnd = merged.last { $0.stage != .wake }?.end ?? g.end
        s.disturbances = merged.filter { $0.stage == .wake && $0.start > onset && $0.end < lastSleepEnd && $0.duration >= 60 }.count
        // Cycles: REM periods ≥ 5 min, separated by ≥ 15 min of NREM.
        var cycles = 0
        var lastRemEnd: Int?
        for seg in merged where seg.stage == .rem && seg.duration >= 300 {
            if lastRemEnd.map({ seg.start - $0 >= 900 }) ?? true { cycles += 1 }
            lastRemEnd = seg.end
        }
        s.cycles = max(cycles, s.asleepSec >= 3 * 3600 ? 1 : 0)

        let slice = TimeIndex.slice(window, from: g.start, to: g.end)
        // Seconds asleep, by walking the segments once.
        var asleepHRSum = 0, asleepHRN = 0
        var skin: [Double] = []
        var spo2: [Double] = []
        var si = 0
        for x in slice {
            while si < merged.count && merged[si].end <= x.ts { si += 1 }
            guard si < merged.count, merged[si].start <= x.ts, merged[si].stage != .wake else { continue }
            if x.hr > 0 {
                asleepHRSum += Int(x.hr); asleepHRN += 1
                if !x.skinTemp.isNaN, x.skinTemp >= 28, x.skinTemp <= 42 { skin.append(Double(x.skinTemp)) }
            }
            if x.spo2Raw >= 90 && x.spo2Raw <= 100 { spo2.append(Double(x.spo2Raw)) }
        }
        if asleepHRN > 0 { s.avgHR = (Double(asleepHRSum) / Double(asleepHRN)).rounded() }
        if nap { return s }

        let spans = g.runs.map { (start: $0.start, end: $0.end) }
        // HRV: mean of the 5-minute RMSSD windows across the night (gap-aware).
        let beats = HRV.beats(slice)
        if let h = HRV.sessionRMSSD(beats, spans: spans), h.rmssd >= 5, h.rmssd <= 250 {
            s.hrv = (h.rmssd * 10).rounded() / 10
            s.hrvWindows = h.windows
            s.hrvNoise = h.acf1.map { ($0 * 100).rounded() / 100 }
        }
        // Resting heart rate: lowest 30-minute mean of the night.
        if let r = Vitals.restingHR(window, windows: spans) { s.rhr = (r * 10).rounded() / 10 }
        if let rr = HRV.respiratoryRate(beats, spans: spans) { s.respRate = (rr * 100).rounded() / 100 }
        if spo2.count >= 20 { s.spo2 = Stats.mean(spo2).map { ($0 * 10).rounded() / 10 } }
        if skin.count >= 300 { s.skinTemp = Stats.median(skin).map { ($0 * 100).rounded() / 100 } }

        // High stress during sleep: share of the minutes asleep whose 5-minute mean heart rate
        // sits at least 40 % above the night's resting level.
        if let rhr = s.rhr, rhr > 0 {
            var high = 0, total = 0
            var segIdx = 0
            let a = max(0, series.index(of: g.start)), b = min(series.count, series.index(of: g.end))
            if b > a {
                for i in a..<b {
                    let t = series.unix(i)
                    while segIdx < merged.count && merged[segIdx].end <= t { segIdx += 1 }
                    guard segIdx < merged.count, merged[segIdx].start <= t, merged[segIdx].stage != .wake else { continue }
                    var sum = 0.0, n = 0
                    for k in max(a, i - 2)...min(b - 1, i + 2) where series.hrN[k] > 0 {
                        sum += series.hrSum[k]; n += series.hrN[k]
                    }
                    guard n > 0 else { continue }
                    total += 1
                    if sum / Double(n) >= 1.4 * rhr { high += 1 }
                }
            }
            if total >= 30 { s.highStressPct = (Double(high) / Double(total) * 100).rounded() }
        }
        return s
    }

    // MARK: - Activities

    static func scoreActivity(_ a: ActivityRecord, samples: [HistorySample], rest: Double, maxHR: Double,
                              profile: UserProfile, cal: Calibration? = nil) -> ActivityRecord {
        var r = a
        let slice = TimeIndex.slice(samples, from: a.start, to: a.end)
        let hr = slice.filter { $0.hr > 0 }
        guard hr.count >= 30 else {
            // No heart rate for this window (strap not worn): estimate calories from the
            // activity's MET value and body weight, as a gross figure.
            if a.source != .auto, let met = SportCatalog.info(a.sport)?.met {
                r.calories = (met * profile.weightKg * Double(a.durationSec) / 3600).rounded()
            }
            return r
        }
        var acc = Strain.Accumulator(rest: rest, maxHR: maxHR, denominator: cal?.strainDenominator ?? Strain.defaultDenominator)
        var zones = Array(repeating: 0, count: 6)
        var kcal = 0.0
        var prevTs: Int?
        var hrSum = 0.0, wSum = 0.0
        for s in hr {
            let dt = Double(min(max(1, s.ts - (prevTs ?? s.ts - 1)), 120))
            prevTs = s.ts
            let h = Double(s.hr)
            acc.add(h, weight: dt / 60)
            zones[Strain.zone(h, rest: rest, maxHR: maxHR)] += Int(dt)
            kcal += Strain.kcalForMinute(hr: h, asleep: false, rest: rest, maxHR: maxHR, profile: profile,
                                         activeScale: cal?.kcalActiveScale ?? 1).total * dt / 60
            hrSum += h * dt
            wSum += dt
        }
        r.strain = (acc.strain * 10).rounded() / 10
        r.avgHR = wSum > 0 ? (hrSum / wSum).rounded() : nil
        r.maxHR = sustainedPeak(slice)
        r.calories = kcal.rounded()
        r.zoneSeconds = zones
        return r
    }

    /// Highest HR held by 5 consecutive readings within a minute (rejects single spikes).
    static func sustainedPeak(_ s: ArraySlice<HistorySample>) -> Int? {
        let hr = s.filter { $0.hr > 0 }
        guard hr.count >= 5 else { return hr.map { Int($0.hr) }.max() }
        var best: Int?
        let arr = Array(hr)
        for i in 0...(arr.count - 5) where arr[i + 4].ts - arr[i].ts <= 60 {
            let held = Int(arr[i..<(i + 5)].map(\.hr).min() ?? 0)
            best = max(best ?? held, held)
        }
        return best
    }

    static func guessSport(_ s: ArraySlice<HistorySample>) -> String {
        var walk = 0, run = 0, n = 0
        for x in s where x.activityClass >= 0 {
            n += 1
            if x.activityClass == 1 { walk += 1 } else if x.activityClass == 2 { run += 1 }
        }
        guard n > 60 else { return "activite" }
        if Double(run) > 0.4 * Double(n) { return "course" }
        if Double(walk) > 0.4 * Double(n) { return "marche" }
        return "activite"
    }
}
