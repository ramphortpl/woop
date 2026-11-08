import XCTest
@testable import WoopCore

/// End-to-end checks of the analytics pipeline on a synthetic but physiologically shaped
/// multi-day recording (band sleep states, RSA-modulated R-R, a daily workout).
final class AnalyticsTests: XCTestCase {
    struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double {
            let u = max(next(), 1e-12), v = next()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    /// Stage at `m` minutes after sleep onset in a textbook night of 90-min cycles.
    static func stageAt(_ m: Double) -> SleepStage {
        if (95..<98).contains(m) || (300..<303).contains(m) { return .wake } // two brief awakenings
        let cycle = Int(m / 90), inCycle = m.truncatingRemainder(dividingBy: 90)
        let deep = [40.0, 30, 15, 5, 0, 0][min(cycle, 5)]
        let rem = [10.0, 20, 25, 30, 35, 35][min(cycle, 5)]
        if inCycle < 25 { return .light }
        if inCycle < 25 + deep { return .deep }
        if inCycle < 90 - rem { return .light }
        return .rem
    }

    /// Synthetic days: sleep 23:30 → 07:15, workout 18:00–19:00, otherwise light activity.
    static func makeSamples(days: Int, startKey: String, hrvScale: [Double]) -> [HistorySample] {
        var rng = Rng(state: 42)
        var out: [HistorySample] = []
        guard let day0 = DayKey.startUnix(startKey) else { return [] }
        var stepCounter = 1000
        var beatPhase = 0.0
        var hrSlow = 0.0
        for d in 0..<days {
            let base = day0 + d * 86400
            let scale = hrvScale[min(d, hrvScale.count - 1)]
            for t in stride(from: base - 30 * 60, to: base + 86400 - 30 * 60, by: 1) {
                let sinceMidnight = t - base
                let asleep = sinceMidnight < 7 * 3600 + 15 * 60 || sinceMidnight >= 23 * 3600 + 30 * 60
                let workout = sinceMidnight >= 18 * 3600 && sinceMidnight < 19 * 3600
                var s = HistorySample(ts: t, hr: 0)
                var hr: Double
                var rsaAmp: Double
                var breath = 14.0
                var still = 0.0005
                hrSlow = 0.98 * hrSlow + 0.02 * rng.gauss()
                if asleep {
                    let into = Double((sinceMidnight + 86400 - (23 * 3600 + 30 * 60)) % 86400) / 60
                    let st = into < 12 ? SleepStage.wake : stageAt(into - 12)
                    switch st {
                    case .deep: hr = 49 + hrSlow * 0.3 + rng.gauss() * 0.3; rsaAmp = 45 * scale; breath = 13
                    case .light: hr = 54 + hrSlow * 1.5 + rng.gauss() * 1.0; rsaAmp = 30 * scale
                    case .rem: hr = 58 + hrSlow * 4 + rng.gauss() * 2.5; rsaAmp = 18 * scale; breath = 16 + rng.gauss() * 2
                    case .wake: hr = 66 + rng.gauss() * 3; rsaAmp = 12; still = 0.08
                    }
                    s.sleepState = into < 20 ? 1 : (st == .wake ? 0 : 2)
                } else if workout {
                    hr = 150 + rng.gauss() * 4; rsaAmp = 4; still = 0.2; s.sleepState = 0
                } else {
                    hr = 72 + rng.gauss() * 4; rsaAmp = 15; still = 0.03; s.sleepState = 0
                }
                s.hr = UInt8(max(30, min(220, hr.rounded())))
                var rr: [Int] = []
                let meanRR = 60000 / hr
                beatPhase += 1000
                while beatPhase >= meanRR {
                    let rsa = sin(2 * .pi * Double(t) * breath / 60) * rsaAmp
                    rr.append(Int((meanRR + rsa + rng.gauss() * 4).rounded()))
                    beatPhase -= meanRR
                }
                s.setRR(rr)
                s.gx = Float(0.1 + rng.gauss() * still)
                s.gy = Float(0.2 + rng.gauss() * still)
                s.gz = Float(0.97 + rng.gauss() * still)
                if !asleep && rng.next() < (workout ? 0.9 : 0.15) { stepCounter = (stepCounter + (workout ? 2 : 1)) & 0xFFFF }
                s.stepCounter = Int32(stepCounter)
                s.activityClass = workout ? 2 : 0
                s.skinTemp = asleep ? 33.5 : 32.0
                out.append(s)
            }
        }
        return out
    }

    func testMultiDayPipeline() {
        let start = "2026-10-01"
        let days = 7
        let samples = Self.makeSamples(days: days, startKey: start, hrvScale: [1, 1, 1, 1, 1, 1.4, 0.6])
        XCTAssertGreaterThan(samples.count, 500_000)
        var history: [DayMetrics] = []
        var profile = UserProfile()
        profile.birthYear = 1990
        let now = DayKey.startUnix(DayKey.adding(days, to: start))! + 6 * 3600
        let t0 = Date()
        for d in 0..<days {
            let key = DayKey.adding(d, to: start)
            let m = DayEngine.compute(DayInputs(date: key, samples: samples, profile: profile, history: history, now: now))
            history.append(m)
            let s = m.sleep
            print(String(format: "%@ sleep=%@ asleep=%.2fh eff=%.0f%% deep=%.0fm rem=%.0fm hrv=%@ rhr=%@ resp=%@ perf=%@ rec=%@ strain=%@ kcal=%@ steps=%@ acts=%d",
                         key, s.map { _ in "yes" } ?? "no", Double(s?.asleepSec ?? 0) / 3600, (s?.efficiency ?? 0) * 100,
                         Double(s?.deepSec ?? 0) / 60, Double(s?.remSec ?? 0) / 60,
                         m.hrv.map { "\($0)" } ?? "-", m.rhr.map { "\($0)" } ?? "-", m.respRate.map { "\($0)" } ?? "-",
                         m.sleepPerformance.map { String(format: "%.0f", $0) } ?? "-", m.recovery.map { "\($0)" } ?? "-",
                         m.strain.map { "\($0)" } ?? "-", m.calories.map { "\($0)" } ?? "-", m.steps.map { "\($0)" } ?? "-", m.activities.count))
        }
        print("elapsed", Date().timeIntervalSince(t0))
        // Day 1+ have a full night before them.
        let d2 = history[2]
        XCTAssertNotNil(d2.sleep)
        if let s = d2.sleep {
            XCTAssertEqual(Double(s.asleepSec) / 3600, 7.5, accuracy: 1.2)
            XCTAssertGreaterThan(s.deepSec, 0)
            XCTAssertGreaterThan(s.remSec, 0)
        }
        XCTAssertNotNil(d2.hrv)
        XCTAssertNotNil(d2.rhr)
        if let r = d2.rhr { XCTAssertEqual(r, 52, accuracy: 4) }
        if let rr = d2.respRate { XCTAssertEqual(rr, 14, accuracy: 2) }
        XCTAssertNotNil(d2.strain)
        if let st = d2.strain { XCTAssertGreaterThan(st, 8); XCTAssertLessThan(st, 19) }
        XCTAssertEqual(d2.activities.count, 1)
        XCTAssertEqual(d2.activities.first?.sport, "course")
        // Recovery appears once calibrated, and tracks the HRV change.
        XCTAssertNotNil(history[5].recovery)
        if let hi = history[5].recovery, let lo = history[6].recovery {
            XCTAssertGreaterThan(hi, lo)
        }
    }

    func testStrainAnchors() {
        // 60 min at 105 bpm vs 90 min at 165 bpm (RHR 60, HRmax 187, quiet 0.20 HRR).
        func strain(_ hr: Double, _ minutes: Int) -> Double {
            var a = Strain.Accumulator(rest: 60, maxHR: 187, quietHRR: 0.20, female: false)
            for _ in 0..<minutes { a.add(hr) }
            return a.strain
        }
        XCTAssertEqual(strain(105, 60), 3, accuracy: 1.5)
        XCTAssertEqual(strain(145, 45), 8.9, accuracy: 1.5)
        XCTAssertEqual(strain(165, 90), 16.7, accuracy: 1.5)
        XCTAssertEqual(strain(80, 600), 0, accuracy: 0.5)
    }

    func testRecoveryLogisticCentre() {
        let b = Recovery.Baselines(hrv: Baseline(mean: 60, sigma: 8, n: 10), rhr: Baseline(mean: 52, sigma: 2, n: 10), resp: nil)
        let atBaseline = Recovery.score(.init(hrv: 60, rhr: 52, resp: nil, sleepPerformance: 85, skinTempDev: nil), b)!
        XCTAssertEqual(atBaseline, 58, accuracy: 3)
        let great = Recovery.score(.init(hrv: 80, rhr: 48, resp: nil, sleepPerformance: 100, skinTempDev: nil), b)!
        let poor = Recovery.score(.init(hrv: 40, rhr: 58, resp: nil, sleepPerformance: 50, skinTempDev: nil), b)!
        XCTAssertGreaterThan(great, 85)
        XCTAssertLessThan(poor, 20)
    }
}

final class LiveMixTests: XCTestCase {
    /// A night synced from history followed by a whole day seen only through the live HR stream
    /// (no band state, no motion) must still be detected and staged from the band envelope.
    func testNightDetectedDespiteLongLiveOnlyDay() {
        let start = "2026-10-01"
        var samples = AnalyticsTests.makeSamples(days: 3, startKey: start, hrvScale: [1])
        let dayStart = DayKey.startUnix("2026-10-03")!
        for i in samples.indices where samples[i].ts >= dayStart + 8 * 3600 {
            var s = HistorySample(ts: samples[i].ts, hr: samples[i].hr)
            s.setRR(samples[i].rr)
            samples[i] = s // live-only second: HR + R-R, nothing else
        }
        let now = dayStart + 23 * 3600
        let m = DayEngine.compute(DayInputs(date: "2026-10-03", samples: samples, profile: UserProfile(), history: [], now: now))
        XCTAssertNotNil(m.sleep)
        XCTAssertTrue(m.sleep?.bandDetected ?? false)
        XCTAssertNotNil(m.strain)
    }
}
