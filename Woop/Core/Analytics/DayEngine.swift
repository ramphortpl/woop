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
}

/// Computes a WHOOP-style day: the night that ended on `date` (sleep + recovery), then the
/// strain cycle that runs until the next night begins.
enum DayEngine {
    static func compute(_ inp: DayInputs) -> DayMetrics {
        var out = DayMetrics(date: inp.date)
        out.computedAt = inp.now
        guard let dayStart = DayKey.startUnix(inp.date),
              let nextStart = DayKey.startUnix(DayKey.adding(1, to: inp.date)) else { return out }
        let samples = inp.samples
        let from = dayStart - 12 * 3600
        let to = min(inp.now, nextStart + 12 * 3600)
        guard to > from, !samples.isEmpty else { return out }
        let series = MinuteSeries.build(TimeIndex.slice(samples, from: from, to: to).map { $0 }, from: from, to: to)
        let profile = inp.profile
        let history = inp.history
        let female = profile.sex == .female

        // ── Sleep detection & assignment ──────────────────────────────────────────────
        let candidates = SleepDetector.detect(series)
        let mainMinAsleep = 90
        let todays = candidates.filter { $0.end > dayStart && $0.end <= nextStart }
        let main = todays.filter { $0.asleepMinutes >= mainMinAsleep }.max { $0.asleepMinutes < $1.asleepMinutes }
        let tomorrows = candidates.filter { $0.end > nextStart && $0.asleepMinutes >= mainMinAsleep && $0.start > (main?.end ?? dayStart) }
        let nextMain = tomorrows.min { $0.start < $1.start }
        let napCands = todays.filter { c in
            c != main && c.asleepMinutes >= 15 && c.start >= (main?.end ?? dayStart) && c.end - c.start <= 4 * 3600
        }

        var sleep: SleepSession?
        if let m = main {
            sleep = summarizeSleep(m, samples: samples, series: series, nap: false)
        }
        let naps = napCands.map { summarizeSleep($0, samples: samples, series: series, nap: true) }
        out.sleep = sleep
        out.naps = naps

        // ── Sleep need / performance / debt / consistency ─────────────────────────────
        let prev = history.last { $0.date == DayKey.adding(-1, to: inp.date) }
        // Shortfall is measured against each night's INTRINSIC need (baseline + strain − naps),
        // never against a need that already contained earlier debt — otherwise debt compounds.
        let prevNights: [(need: Double, slept: Double)] = history.suffix(4).reversed().compactMap { d in
            guard let need = d.sleepNeedSec, let s = d.sleep else { return nil }
            return (need - (d.sleepDebtSec ?? 0), Double(s.asleepSec))
        }
        let debtIn = SleepCoach.debtSec(previousNights: prevNights)
        let prevNapSec = Double(prev?.naps.reduce(0) { $0 + $1.asleepSec } ?? 0)
        let need = SleepCoach.needSec(baselineHours: profile.baselineSleepNeedHours, priorStrain: prev?.strain,
                                      debtSec: debtIn, napSec: prevNapSec)
        out.sleepDebtSec = debtIn
        if let s = sleep {
            out.sleepNeedSec = need
            out.sleepPerformance = SleepCoach.performance(asleepSec: s.asleepSec, needSec: need)
            let nights = history.compactMap(\.sleep) + [s]
            out.sleepConsistency = SleepCoach.consistency(nights)
            out.hrv = s.hrv
            out.rhr = s.rhr
            out.respRate = s.respRate
            out.spo2 = s.spo2
            out.skinTemp = s.skinTemp
        }

        // ── Cycle window ──────────────────────────────────────────────────────────────
        let cycleStart = sleep?.start ?? dayStart
        var cycleEnd = nextMain?.start ?? min(inp.now, nextStart)
        if nextMain == nil && inp.now >= nextStart + 12 * 3600 { cycleEnd = nextStart }
        cycleEnd = max(cycleEnd, cycleStart)
        out.cycleStart = cycleStart
        out.cycleEnd = cycleEnd

        // Minute flags: asleep (main or naps) inside the cycle.
        let sleepWindows: [(Int, Int)] = ([sleep] + naps.map { Optional($0) }).compactMap { $0 }.map { ($0.start, $0.end) }
        func isAsleep(_ unix: Int) -> Bool { sleepWindows.contains { unix >= $0.0 && unix < $0.1 } }

        // ── Anchors: resting HR, max HR, quiet level ──────────────────────────────────
        let recentRHR = history.suffix(14).compactMap(\.rhr) + [sleep?.rhr].compactMap { $0 }
        let restHR = sleep?.rhr ?? Stats.median(recentRHR) ?? 60
        let observedPeaks = history.suffix(30).compactMap { $0.maxHR.map(Double.init) }
        var maxHR = profile.tanakaMaxHR
        if let o = profile.maxHROverride, o > 100 { maxHR = Double(o) }
        else if let p = observedPeaks.max(), observedPeaks.count >= 3 {
            let secondBest = observedPeaks.sorted(by: >).dropFirst().first ?? p
            maxHR = max(maxHR, min(secondBest, 215))
        }
        out.restingHRUsed = restHR
        out.maxHRUsed = maxHR

        let i0 = max(0, series.index(of: cycleStart)), i1 = min(series.count, series.index(of: cycleEnd))
        var awakeMinuteHR: [Double] = []
        var wornMinutes = 0
        if i1 > i0 {
            for i in i0..<i1 {
                if series.worn(i) { wornMinutes += 1 }
                if let h = series.hr(i), !isAsleep(series.unix(i)) { awakeMinuteHR.append(h) }
            }
        }
        out.wornMinutes = wornMinutes
        let todayQuiet = Strain.dailyQuietHRR(minuteHR: awakeMinuteHR, rest: restHR, maxHR: maxHR)
        out.quietHRR = todayQuiet
        let quietHistory = history.suffix(28).compactMap(\.quietHRR)
        let quiet = quietHistory.count >= 3 ? (Stats.median(quietHistory) ?? Strain.defaultQuietHRR)
            : (todayQuiet ?? Strain.defaultQuietHRR)

        // ── Strain, zones, calories, steps over the cycle ─────────────────────────────
        var acc = Strain.Accumulator(rest: restHR, maxHR: maxHR, quietHRR: quiet, female: female)
        var curve: [Double] = []
        var kcal = 0.0, active = 0.0, steps = 0
        var hrSum = 0.0, hrN = 0
        if i1 > i0 {
            for i in i0..<i1 {
                let u = series.unix(i)
                let asleep = isAsleep(u)
                let h = series.hr(i)
                if let h, !asleep { acc.add(h) }
                if let h { hrSum += h; hrN += 1 }
                let k = Strain.kcalForMinute(hr: h, asleep: asleep, rest: restHR, maxHR: maxHR, profile: profile)
                kcal += k.total
                active += k.active
                steps += series.stepInc[i]
                if (i - i0) % 15 == 14 { curve.append((acc.strain * 10).rounded() / 10) }
            }
        }
        curve.append((acc.strain * 10).rounded() / 10)
        let cycleSlice = TimeIndex.slice(samples, from: cycleStart, to: cycleEnd)
        var zones = Array(repeating: 0, count: 6)
        var hrSeconds: [Double] = []
        for s in cycleSlice where s.hr > 0 && !isAsleep(s.ts) {
            zones[Strain.zone(Double(s.hr), maxHR: maxHR)] += 1
            hrSeconds.append(Double(s.hr))
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
                              : scoreActivity(a, samples: samples, rest: restHR, maxHR: maxHR, quiet: quiet, profile: profile))
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
                activities.append(scoreActivity(rec, samples: samples, rest: restHR, maxHR: maxHR, quiet: quiet, profile: profile))
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
            if let score = Recovery.score(inputs, b) {
                out.recovery = score.rounded()
            } else {
                out.calibrationNights = min(Recovery.calibrationNights - 1, history.compactMap(\.hrv).count) + 1
            }
        }

        // ── Tonight's need, fitness, trace ────────────────────────────────────────────
        var nightsForDebt: [(need: Double, slept: Double)] = []
        if let s = sleep { nightsForDebt.append((need - debtIn, Double(s.asleepSec))) }
        nightsForDebt += prevNights
        let debtTonight = SleepCoach.debtSec(previousNights: nightsForDebt)
        let napSec = Double(naps.reduce(0) { $0 + $1.asleepSec })
        out.tonightNeedSec = SleepCoach.needSec(baselineHours: profile.baselineSleepNeedHours, priorStrain: out.strain,
                                                debtSec: debtTonight, napSec: napSec)
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

    static func summarizeSleep(_ c: SleepDetector.Candidate, samples: [HistorySample], series: MinuteSeries, nap: Bool) -> SleepSession {
        var s = SleepSession(start: c.start, end: c.end, isNap: nap)
        s.bandDetected = c.bandBased
        let stages = SleepStager.stage(samples: samples, start: c.start, end: c.end)
        s.stages = stages
        for g in stages {
            switch g.stage {
            case .wake: s.awakeSec += g.duration
            case .light: s.lightSec += g.duration
            case .deep: s.deepSec += g.duration
            case .rem: s.remSec += g.duration
            }
        }
        // Latency: time to the first sustained (≥ 5 min) sleep.
        var run = 0
        var onset = c.start
        outer: for g in stages {
            if g.stage == .wake { run = 0; continue }
            run += g.duration
            if run >= 300 { onset = g.end - run; break outer }
        }
        s.latencySec = max(0, onset - c.start)
        // Disturbances: wake bouts ≥ 1 min after onset, before the final wake.
        let lastSleepEnd = stages.last { $0.stage != .wake }?.end ?? c.end
        s.disturbances = stages.filter { $0.stage == .wake && $0.start > onset && $0.end < lastSleepEnd && $0.duration >= 60 }.count
        // Cycles: REM periods ≥ 5 min, separated by ≥ 15 min of NREM.
        var cycles = 0
        var lastRemEnd: Int?
        for g in stages where g.stage == .rem && g.duration >= 300 {
            if lastRemEnd.map({ g.start - $0 >= 900 }) ?? true { cycles += 1 }
            lastRemEnd = g.end
        }
        s.cycles = max(cycles, s.asleepSec >= 3 * 3600 ? 1 : 0)

        let slice = TimeIndex.slice(samples, from: c.start, to: c.end)
        func asleepAt(_ t: Int) -> Bool {
            guard let g = stages.first(where: { t >= $0.start && t < $0.end }) else { return false }
            return g.stage != .wake
        }
        let asleepHR = slice.filter { $0.hr > 0 && asleepAt($0.ts) }.map { Double($0.hr) }
        s.avgHR = Stats.mean(asleepHR).map { $0.rounded() }
        if nap { return s }

        // HRV — WHOOP weights the night toward its last slow-wave sleep: use 5-min RMSSD windows
        // overlapping deep sleep in the second half; otherwise every asleep window.
        let beats = HRV.beats(slice)
        let windows = HRV.windowedRMSSD(beats, from: onset, to: lastSleepEnd)
        let half = onset + (lastSleepEnd - onset) / 2
        func deepOverlap(_ w: Int) -> Bool {
            stages.contains { $0.stage == .deep && $0.end > w && $0.start < w + 300 }
        }
        let late = windows.filter { $0.start >= half && deepOverlap($0.start) }.map(\.value)
        let all = windows.filter { asleepAt($0.start + 150) }.map(\.value)
        if late.count >= 2 {
            s.hrv = Stats.median(late).map { $0.rounded() }
        } else if all.count >= 3 {
            s.hrv = Stats.median(all).map { $0.rounded() }
        } else {
            // Sparse beat stream: pool every clean successive difference of the night.
            let d = HRV.successiveDiffs(HRV.window(beats, from: onset, to: lastSleepEnd))
            if d.count >= 40, let v = HRV.rmssd(d), v >= 5, v <= 250 { s.hrv = v.rounded() }
        }

        // Resting HR: mean of deep-sleep minutes in the last 60 % of the night, else a low percentile.
        let cut = onset + Int(Double(lastSleepEnd - onset) * 0.4)
        var deepMinuteHR: [Double] = []
        for g in stages where g.stage == .deep && g.end > cut {
            let a = max(0, series.index(of: max(g.start, cut))), b = min(series.count, series.index(of: g.end))
            if b > a { for i in a..<b { if let h = series.hr(i) { deepMinuteHR.append(h) } } }
        }
        if deepMinuteHR.count >= 10 {
            s.rhr = Stats.mean(deepMinuteHR).map { $0.rounded() }
        } else {
            s.rhr = Stats.percentile(asleepHR, 15).map { $0.rounded() }
        }

        s.respRate = HRV.respiratoryRate(beats, from: onset, to: lastSleepEnd).map { ($0 * 10).rounded() / 10 }

        let spo2 = slice.compactMap { x -> Double? in
            guard x.spo2Raw > 0 else { return nil }
            let v = Double(Int(x.spo2Raw) & 0x7F)
            return (85...100).contains(v) && asleepAt(x.ts) ? v : nil
        }
        if spo2.count >= 5 { s.spo2 = Stats.median(spo2).map { ($0 * 10).rounded() / 10 } }

        let skin = slice.compactMap { x -> Double? in
            x.skinTemp.isNaN || !asleepAt(x.ts) ? nil : Double(x.skinTemp)
        }
        if skin.count >= 300 { s.skinTemp = Stats.median(skin).map { ($0 * 100).rounded() / 100 } }
        return s
    }

    // MARK: - Activities

    static func scoreActivity(_ a: ActivityRecord, samples: [HistorySample], rest: Double, maxHR: Double,
                              quiet: Double, profile: UserProfile) -> ActivityRecord {
        var r = a
        let slice = TimeIndex.slice(samples, from: a.start, to: a.end)
        let hr = slice.filter { $0.hr > 0 }
        guard hr.count >= 30 else { return r }
        var acc = Strain.Accumulator(rest: rest, maxHR: maxHR, quietHRR: quiet, female: profile.sex == .female)
        var zones = Array(repeating: 0, count: 6)
        var minute = slice.first?.ts ?? a.start
        var mSum = 0.0, mN = 0
        var kcal = 0.0
        for s in hr {
            zones[Strain.zone(Double(s.hr), maxHR: maxHR)] += 1
            if s.ts - minute >= 60 {
                if mN > 0 {
                    let h = mSum / Double(mN)
                    acc.add(h)
                    kcal += Strain.kcalForMinute(hr: h, asleep: false, rest: rest, maxHR: maxHR, profile: profile).total
                }
                minute = s.ts
                mSum = 0; mN = 0
            }
            mSum += Double(s.hr); mN += 1
        }
        if mN >= 20 {
            let h = mSum / Double(mN)
            acc.add(h, weight: Double(mN) / 60)
            kcal += Strain.kcalForMinute(hr: h, asleep: false, rest: rest, maxHR: maxHR, profile: profile).total * Double(mN) / 60
        }
        r.strain = (acc.strain * 10).rounded() / 10
        r.avgHR = Stats.mean(hr.map { Double($0.hr) }).map { $0.rounded() }
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
