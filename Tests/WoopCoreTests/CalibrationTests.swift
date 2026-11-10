import XCTest
@testable import WoopCore

final class HRVTests: XCTestCase {
    /// A regular tachogram with known RMSSD, as one beat per second-record.
    func beats(count: Int, base: Double = 1000, amp: Double = 30, drop: Set<Int> = [], spikes: [Int: Double] = [:]) -> [HRV.Beat] {
        var out: [HRV.Beat] = []
        var t = 1_800_000_000.0
        for i in 0..<count {
            var rr = base + amp * sin(2 * .pi * Double(i) / 4.2)
            if let s = spikes[i] { rr = s }
            t += rr / 1000
            if drop.contains(i) { continue }
            out.append(HRV.Beat(ts: Int(t), rr: rr.rounded()))
        }
        return out
    }

    func testCleanSeriesMatchesTextbookRMSSD() {
        let b = beats(count: 2000)
        var d: [Double] = []
        for i in 1..<b.count { d.append(b[i].rr - b[i - 1].rr) }
        let truth = (d.reduce(0) { $0 + $1 * $1 } / Double(d.count)).squareRoot()
        let h = HRV.sessionRMSSD(b, start: b.first!.ts, end: b.last!.ts + 1)!
        XCTAssertEqual(h.rmssd, truth, accuracy: truth * 0.03)
        XCTAssertGreaterThan(h.windows, 4)
        XCTAssertFalse(h.pooled)
    }

    /// Dropped beats and artefacts must not manufacture differences across the gap
    /// (the defect that inflated WHOOP 5.0 / MG nights by 51–102 %).
    func testMissingBeatsAndArtefactsDoNotInflate() {
        let clean = beats(count: 3000)
        var drop = Set<Int>()
        var spikes: [Int: Double] = [:]
        for i in stride(from: 17, to: 3000, by: 23) { drop.insert(i) }       // 4 % of beats never timed
        for i in stride(from: 9, to: 3000, by: 41) { spikes[i] = 1700 }      // missed-beat style artefacts
        let dirty = beats(count: 3000, drop: drop, spikes: spikes)
        let a = HRV.sessionRMSSD(clean, start: clean.first!.ts, end: clean.last!.ts + 1)!.rmssd
        let b = HRV.sessionRMSSD(dirty, start: dirty.first!.ts, end: dirty.last!.ts + 1)!.rmssd
        XCTAssertEqual(b, a, accuracy: a * 0.10)
        // What a naive successive difference over the compacted list would have reported.
        var naive: [Double] = []
        for i in 1..<dirty.count { naive.append(dirty[i].rr - dirty[i - 1].rr) }
        let naiveRMSSD = (naive.reduce(0) { $0 + $1 * $1 } / Double(naive.count)).squareRoot()
        XCTAssertGreaterThan(naiveRMSSD, a * 1.5)
    }

    func testDuplicatedBeatsAreRefused() {
        let b = beats(count: 1500)
        var doubled: [HRV.Beat] = []
        for x in b { doubled.append(x); doubled.append(x) }                   // every beat stored twice
        XCTAssertNil(HRV.sessionRMSSD(doubled, start: b.first!.ts, end: b.last!.ts + 1))
    }

    func testRunsBreakOnRejectedBeats() {
        let ts = 1_800_000_000
        let rr: [Double] = [1000, 1010, 990, 1700, 1005, 995, 250, 1000, 1002]
        let b = rr.enumerated().map { HRV.Beat(ts: ts + $0.offset, rr: $0.element) }
        let runs = HRV.cleanRuns(b[...])
        XCTAssertEqual(runs, [[1000, 1010, 990], [1005, 995], [1000, 1002]])
    }
}

final class CalibrationTests: XCTestCase {
    /// A synthetic WHOOP export produced by KNOWN formulas: the fit must find them back.
    static func whoopHistory(days: Int, seed: UInt64 = 3) -> [DayMetrics] {
        var rng = AnalyticsTests.Rng(state: seed)
        var out: [DayMetrics] = []
        var debt = 0.0
        var prevStrain = 10.0
        var hrvHist: [Double] = [], rhrHist: [Double] = []
        let day0 = DayKey.startUnix("2026-05-01")!
        for i in 0..<days {
            let key = DayKey.adding(i, to: "2026-05-01")
            var d = DayMetrics(date: key)
            d.imported = true
            let need = 7.6 * 3600 + 110 * prevStrain * prevStrain / 21 + debt          // base + strain² + debt
            let asleep = (6.2 + rng.next() * 2.4) * 3600
            let inBed = asleep / (0.86 + rng.next() * 0.1)
            let bed = day0 + i * 86400 - 3600 + Int(rng.gauss() * 2400)
            var s = SleepSession(start: bed, end: bed + Int(inBed))
            s.lightSec = Int(asleep * 0.47); s.deepSec = Int(asleep * 0.28); s.remSec = Int(asleep) - s.lightSec - s.deepSec
            s.awakeSec = Int(inBed - asleep)
            d.sleep = s
            d.sleepNeedSec = need
            d.sleepDebtSec = debt
            let hours = min(100, asleep / need * 100)
            let cons = 55 + rng.next() * 35
            d.sleepConsistency = cons
            d.sleepPerformance = (0.6 * hours + 0.1 * cons + 0.2 * s.efficiency * 100 + 10).rounded()
            let hrv = 62 * exp(rng.gauss() * 0.22)
            let rhr = 52 + rng.gauss() * 3
            d.hrv = hrv.rounded(); d.rhr = rhr.rounded(); d.respRate = 15 + rng.gauss() * 0.4
            if hrvHist.count >= 5 {
                let lm = hrvHist.suffix(30).map { log($0) }
                let mean = lm.reduce(0, +) / Double(lm.count)
                let rm = rhrHist.suffix(30).reduce(0, +) / Double(min(30, rhrHist.count))
                let z = 1.9 * (log(hrv) - mean) / 0.22 - 0.5 * (rhr - rm) / 3 + 0.9 * (d.sleepPerformance! - 85) / 12 + 0.3
                d.recovery = (100 / (1 + exp(-z))).rounded()
            }
            hrvHist.append(hrv); rhrHist.append(rhr)
            let strain = 6 + rng.next() * 12
            d.strain = (strain * 10).rounded() / 10
            // One workout a day on a steeper personal scale (D = 3000).
            let zoneMin = [0.0, 10 + rng.next() * 30, 5 + rng.next() * 25, rng.next() * 20, rng.next() * 10, rng.next() * 3]
            var a = ActivityRecord(id: "whoop-\(i)", sport: "course", start: bed + 40_000, end: bed + 40_000 + 5400, source: .imported)
            a.zoneSeconds = zoneMin.map { Int($0 * 60) }
            let zoned = (1...5).reduce(0.0) { $0 + zoneMin[$1] }
            let load = (1...5).reduce(0.0) { $0 + Double($1) * zoneMin[$1] } + 0.2 * (90 - zoned)
            a.strain = 21 * log(load + 1) / log(3000)
            a.avgHR = 140; a.maxHR = 178
            a.calories = 90 * 1.3 * 9
            d.activities = [a]
            out.append(d)
            debt = 0.42 * max(0, need - asleep)
            if debt < 600 { debt = 0 }
            prevStrain = strain
        }
        return out
    }

    func testFitRecoversTheHiddenFormulas() {
        let days = Self.whoopHistory(days: 150)
        let c = Calibration.fit(imported: days, computed: [:], profile: UserProfile(), tz: { _ in 0 })
        XCTAssertEqual(c.whoopNights, 150)
        // Sleep score weights.
        let w = c.perfWeights!
        XCTAssertEqual(w.hours, 0.6, accuracy: 0.05)
        XCTAssertEqual(w.consistency, 0.1, accuracy: 0.04)
        XCTAssertEqual(w.efficiency, 0.2, accuracy: 0.06)
        XCTAssertLessThan(c.perfFit!.mae, 1.0)
        // Need: base 7,6 h and a quadratic strain term; debt carry 0,42.
        XCTAssertEqual(c.need!.baseSec / 3600, 7.6, accuracy: 0.15)
        XCTAssertGreaterThan(c.need!.strainQuadratic, 0)
        XCTAssertEqual(c.debtCarry!, 0.42, accuracy: 0.05)
        // Strain denominator.
        XCTAssertEqual(c.strainDenominator!, 3000, accuracy: 300)
        // Recovery model: predicts WHOOP's own scores much better than the default.
        XCTAssertNotNil(c.recovery)
        XCTAssertLessThan(c.recoveryFit!.mae, 6)
        XCTAssertLessThan(c.recoveryFit!.mae, c.recoveryFit!.defaultMAE! * 0.7)
        XCTAssertGreaterThan(c.recovery!.wLnHRV, 0)
        XCTAssertLessThan(c.recovery!.wRHR, 0)
        // Stage shares.
        XCTAssertEqual(c.stageShares!.deep, 0.28 * 0.9, accuracy: 0.05)
    }

    func testTooLittleDataKeepsDefaults() {
        let c = Calibration.fit(imported: Array(Self.whoopHistory(days: 6)), computed: [:], profile: UserProfile(), tz: { _ in 0 })
        XCTAssertNil(c.perfWeights)
        XCTAssertNil(c.recovery)
        XCTAssertNil(c.need)
        XCTAssertNil(c.strainDenominator)
        XCTAssertNil(c.hrvScale)
    }

    func testOverlapAlignsLocalVitalsOnWhoop() {
        let days = Self.whoopHistory(days: 40)
        var computed: [String: DayMetrics] = [:]
        for d in days.suffix(12) {
            var l = DayMetrics(date: d.date)
            l.sleep = d.sleep
            l.hrvRaw = d.hrv! * 1.25          // the strap-side figure reads 25 % above WHOOP's
            l.rhrRaw = d.rhr! - 3
            computed[d.date] = l
        }
        let c = Calibration.fit(imported: days, computed: computed, profile: UserProfile(), tz: { _ in 0 })
        XCTAssertEqual(c.overlapNights, 12)
        XCTAssertEqual(c.hrvScale!, 0.8, accuracy: 0.02)
        XCTAssertEqual(c.rhrOffset!, 3, accuracy: 0.6)
    }

    /// WHOOP's own night from the wearer's screenshots: 70 % / 54 % / 97 % / 0 % → 76 %.
    func testDefaultSleepScoreReproducesARealWhoopNight() {
        let p = SleepCoach.performance(hoursVsNeed: 70, consistency: 54, efficiency: 97, highStressPct: 0)
        XCTAssertEqual(p.rounded(), 76)
    }

    func testDebtRecurrence() {
        // 8 h needed, 6 h slept → 55 % of the 2 h carried over; a shortfall under 10 min is ignored.
        XCTAssertEqual(SleepCoach.nextDebtSec(previousNeedSec: 8 * 3600, creditedSleepSec: 6 * 3600), 0.55 * 7200, accuracy: 1)
        XCTAssertEqual(SleepCoach.nextDebtSec(previousNeedSec: 8 * 3600, creditedSleepSec: 8 * 3600 - 900), 0)
        XCTAssertEqual(SleepCoach.nextDebtSec(previousNeedSec: 8 * 3600, creditedSleepSec: 9 * 3600), 0)
    }

    func testConsistencyIsTheSleepRegularityIndex() {
        let day = 86400
        let base = 1_790_000_000
        // Four identical nights → 100.
        let same = (0..<4).map { (start: base + $0 * day, end: base + $0 * day + 8 * 3600) }
        XCTAssertEqual(SleepCoach.consistency(same, tz: { _ in 0 })!, 100, accuracy: 0.01)
        // Shifted by one hour every night: 2 h of mismatch out of 24 → SRI 83.
        let shifted = (0..<4).map { (start: base + $0 * day + $0 * 3600, end: base + $0 * day + $0 * 3600 + 8 * 3600) }
        XCTAssertEqual(SleepCoach.consistency(shifted, tz: { _ in 0 })!, 83.3, accuracy: 0.5)
    }

    /// The demo recording (used by the App Store-style screenshots) still yields full days.
    func testDemoDataStillScores() {
        let samples = DemoData.generate(days: 6)
        guard let first = samples.first, let last = samples.last else { return XCTFail("no demo data") }
        var history: [DayMetrics] = []
        var key = DayKey.key(unix: first.ts)
        let lastKey = DayKey.key(unix: last.ts)
        while key <= lastKey {
            let d = DayEngine.compute(DayInputs(date: key, samples: samples, profile: UserProfile(), history: history, now: last.ts))
            history.append(d)
            key = DayKey.adding(1, to: key)
        }
        let withSleep = history.filter { $0.sleep != nil }
        XCTAssertGreaterThanOrEqual(withSleep.count, 4)
        let lastDay = history.last!
        print("demo last day: sleep=\(lastDay.sleep.map { "\($0.asleepSec / 60)m" } ?? "-") perf=\(lastDay.sleepPerformance ?? -1) rec=\(lastDay.recovery ?? -1) strain=\(lastDay.strain ?? -1) hrv=\(lastDay.hrv ?? -1) rhr=\(lastDay.rhr ?? -1) acts=\(lastDay.activities.count) naps=\(lastDay.naps.count)")
        for d in history { print(" demo \(d.date) sleep=\(d.sleep.map { "\($0.asleepSec / 60)m eff=\(Int($0.efficiency * 100))" } ?? "-") rec=\(d.recovery ?? -1) strain=\(d.strain ?? -1) naps=\(d.naps.count) acts=\(d.activities.map { "\($0.sport):\($0.strain ?? -1)" })") }
        XCTAssertNotNil(lastDay.strain)
    }
}
