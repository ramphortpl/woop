import XCTest
@testable import WoopCore

/// Scenario tests of the sleep spine on synthetic but physiologically shaped recordings.
final class SleepScenarioTests: XCTestCase {
    enum Kind { case sleep, quietWake, active, upAtNight, offWrist, missing, liveOnly }

    struct Block {
        var from: Double   // hours since the reference midnight (may exceed 24)
        var to: Double
        var kind: Kind
        /// Strap envelope to write (nil = derive from the kind).
        var band: Int8? = nil
        var hr: Double? = nil
        /// Added to the block's own heart rate (a late meal, alcohol, a fever).
        var hrShift: Double = 0
        /// WHOOP 4.0-like data: no strap envelope at all.
        var noBand = false
    }

    /// Build a recording from blocks. `day0` = local midnight the hours are counted from.
    static func record(day0: Int, _ blocks: [Block], seed: UInt64 = 7) -> [HistorySample] {
        var rng = AnalyticsTests.Rng(state: seed)
        var out: [HistorySample] = []
        var posture = (0.1, 0.2, 0.97)
        var beatPhase = 0.0
        var slow = 0.0
        for b in blocks.sorted(by: { $0.from < $1.from }) {
            let a = day0 + Int(b.from * 3600), e = day0 + Int(b.to * 3600)
            if b.kind == .missing { continue }
            var t = a
            var onset = a
            while t < e {
                var s = HistorySample(ts: t, hr: 0)
                slow = 0.98 * slow + 0.02 * rng.gauss()
                var hr = 72.0, rsa = 15.0, still = 0.03, breath = 14.0
                var band: Int8 = 0
                switch b.kind {
                case .sleep:
                    let into = Double(t - onset) / 60
                    let st = AnalyticsTests.stageAt(into)
                    switch st {
                    case .deep: hr = 50 + slow * 0.3 + rng.gauss() * 0.3; rsa = 45; breath = 13
                    case .light: hr = 54 + slow * 1.5 + rng.gauss(); rsa = 30
                    case .rem: hr = 58 + slow * 4 + rng.gauss() * 2.5; rsa = 18; breath = 16 + rng.gauss() * 2
                    case .wake: hr = 66 + rng.gauss() * 3; rsa = 12
                    }
                    still = st == .wake ? 0.08 : 0.0005
                    band = into < 10 ? 1 : (st == .wake ? 0 : 2)
                    // A position change every ~40 minutes.
                    if rng.next() < 1.0 / 2400 { posture = (rng.gauss() * 0.5, rng.gauss() * 0.5, 0.7) }
                case .quietWake:
                    hr = 63 + slow * 2 + rng.gauss() * 1.5; rsa = 20; still = 0.0008; band = 1
                    if rng.next() < 1.0 / 240 { posture = (rng.gauss() * 0.4, rng.gauss() * 0.4, 0.8) }
                case .active:
                    hr = 74 + slow * 4 + rng.gauss() * 4; rsa = 12; still = 0.04; band = 0
                    // An awake arm keeps changing orientation.
                    if rng.next() < 1.0 / 15 { posture = (rng.gauss() * 0.6, rng.gauss() * 0.6, rng.gauss() * 0.6) }
                case .upAtNight:
                    hr = 82 + rng.gauss() * 4; rsa = 10; still = 0.06; band = 3
                    if rng.next() < 1.0 / 15 { posture = (rng.gauss() * 0.6, rng.gauss() * 0.6, rng.gauss() * 0.6) }
                case .offWrist:
                    hr = 0; still = 0.0002; band = 0
                case .liveOnly:
                    hr = 72 + rng.gauss() * 4; rsa = 15
                case .missing:
                    break
                }
                if let h = b.hr { hr = h + rng.gauss() * 1.5 }
                if hr > 0 { hr += b.hrShift }
                if hr > 0 {
                    s.hr = UInt8(max(30, min(220, hr.rounded())))
                    let meanRR = 60000 / hr
                    var rr: [Int] = []
                    beatPhase += 1000
                    while beatPhase >= meanRR {
                        rr.append(Int((meanRR + sin(2 * .pi * Double(t) * breath / 60) * rsa + rng.gauss() * 4).rounded()))
                        beatPhase -= meanRR
                    }
                    s.setRR(rr)
                }
                if b.kind != .liveOnly {
                    s.gx = Float(posture.0 + rng.gauss() * still)
                    s.gy = Float(posture.1 + rng.gauss() * still)
                    s.gz = Float(posture.2 + rng.gauss() * still)
                    s.sleepState = b.noBand ? -1 : (b.band ?? band)
                    s.skinTemp = 33
                    s.stepCounter = 100
                }
                out.append(s)
                t += 1
                if t == a + 1 { onset = a }
            }
        }
        return out
    }

    func compute(_ date: String, _ samples: [HistorySample], nowHour: Double = 36, history: [DayMetrics] = [],
                 events: [StoredEvent] = []) -> DayMetrics {
        let day0 = DayKey.startUnix(date)!
        return DayEngine.compute(DayInputs(date: date, samples: samples, profile: UserProfile(), history: history,
                                           now: day0 + Int(nowHour * 3600), events: events))
    }

    func hm(_ unix: Int, _ day0: Int) -> String {
        let m = (((unix - day0) / 60) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    func describe(_ tag: String, _ d: DayMetrics, _ day0: Int) {
        if let s = d.sleep {
            print("\(tag): \(hm(s.start, day0))→\(hm(s.end, day0)) inBed=\(s.inBedSec / 60)m asleep=\(s.asleepSec / 60)m awake=\(s.awakeSec / 60)m unobs=\((s.unobservedSec ?? 0) / 60)m eff=\(Int(s.efficiency * 100)) deep=\(s.deepSec / 60) rem=\(s.remSec / 60) hrv=\(s.hrv ?? -1) rhr=\(s.rhr ?? -1) naps=\(d.naps.map { "\(hm($0.start, day0))-\(hm($0.end, day0))" })")
        } else {
            print("\(tag): no sleep; naps=\(d.naps.map { "\(hm($0.start, day0))-\(hm($0.end, day0))" })")
        }
    }

    /// Day 0 afternoon → night → day 1, as hours since day-1 midnight (negative = previous day).
    func testPlainNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.25, kind: .sleep),
            Block(from: 7.25, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("plain", d, day0)
        let s = d.sleep!
        XCTAssertEqual(Double(s.start - day0) / 3600, -0.5, accuracy: 0.2)
        XCTAssertEqual(Double(s.end - day0) / 3600, 7.25, accuracy: 0.2)
        XCTAssertGreaterThan(s.efficiency, 0.9)
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// The strap reports "up" for 25 minutes in the middle of the night: still ONE night.
    func testNightWithLongAwakeningIsOneNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 3.0, kind: .sleep),
            Block(from: 3.0, to: 3.42, kind: .upAtNight),
            Block(from: 3.42, to: 7.5, kind: .sleep),
            Block(from: 7.5, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("awakening", d, day0)
        let s = d.sleep!
        XCTAssertEqual(Double(s.start - day0) / 3600, -0.5, accuracy: 0.25)
        XCTAssertEqual(Double(s.end - day0) / 3600, 7.5, accuracy: 0.25)
        XCTAssertGreaterThan(s.awakeSec, 20 * 60)
        XCTAssertGreaterThan(s.asleepSec, Int(6.5 * 3600))
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Lying still after the final wake with the strap reporting "wake": trimmed.
    func testLieInIsTrimmedByTheStrapEnvelope() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 7.6, kind: .quietWake, band: 0, hr: 60),
            Block(from: 7.6, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("lie-in", d, day0)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 7.0, accuracy: 0.15)
    }

    /// A strap left on the table all night (still, no heart rate) is not sleep.
    func testOffWristIsNotSleep() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -1, kind: .active),
            Block(from: -1, to: 8, kind: .offWrist),
            Block(from: 8, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("off-wrist", d, day0)
        XCTAssertNil(d.sleep)
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// An afternoon nap is a nap, not the night; desk stillness with a normal heart rate is nothing.
    func testNapAndDeskWork() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 10, kind: .active),
            Block(from: 10, to: 11.5, kind: .quietWake, band: 1, hr: 72),   // desk: still, HR not lowered
            Block(from: 11.5, to: 14, kind: .active),
            Block(from: 14, to: 14.75, kind: .sleep),                        // 45-minute nap
            Block(from: 14.75, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("nap", d, day0)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 7.0, accuracy: 0.2)
        XCTAssertEqual(d.naps.count, 1)
        if let n = d.naps.first {
            XCTAssertEqual(Double(n.start - day0) / 3600, 14, accuracy: 0.3)
            XCTAssertGreaterThan(n.asleepSec, 25 * 60)
        }
    }

    /// A recording hole in the middle of the night neither splits the night nor counts as sleep.
    func testHoleInTheNightIsUnobserved() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.0, kind: .sleep),
            Block(from: 2.0, to: 2.75, kind: .missing),
            Block(from: 2.75, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("hole", d, day0)
        let s = d.sleep!
        XCTAssertEqual(Double(s.start - day0) / 3600, -0.5, accuracy: 0.25)
        XCTAssertEqual(Double(s.end - day0) / 3600, 7.0, accuracy: 0.25)
        XCTAssertGreaterThan(s.unobservedSec ?? 0, 35 * 60)
        XCTAssertLessThan(s.asleepSec, Int(7.0 * 3600))
    }

    /// A night seen only through the live stream (heart rate, no motion) is found from heart rate.
    func testLiveOnlyNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        var rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        for i in rec.indices {
            var s = HistorySample(ts: rec[i].ts, hr: rec[i].hr)
            s.setRR(rec[i].rr)
            rec[i] = s
        }
        let d = compute(date, rec)
        describe("live-only", d, day0)
        let s = d.sleep!
        XCTAssertFalse(s.bandDetected)
        XCTAssertEqual(Double(s.asleepSec) / 3600, 7.2, accuracy: 1.0)
    }

    /// Two hours of a film before bed (still, heart rate above the night's level): not sleep.
    func testEveningFilmIsNotSleep() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -3.5, kind: .active),
            Block(from: -3.5, to: -1.6, kind: .quietWake, band: 1, hr: 64),
            Block(from: -1.6, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("film", d, day0)
        XCTAssertEqual(Double(d.sleep!.start - day0) / 3600, -0.5, accuracy: 0.25)
    }
    /// The first part of the night runs 9 bpm high (late meal, alcohol), then a 20-minute
    /// awakening: the strap calls both parts asleep, so it is still one whole night.
    func testElevatedFirstHalfStaysInTheNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.0, kind: .sleep, hrShift: 9),
            Block(from: 2.0, to: 2.35, kind: .upAtNight),
            Block(from: 2.35, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("elevated", d, day0)
        XCTAssertEqual(Double(d.sleep!.start - day0) / 3600, -0.5, accuracy: 0.25)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 7.0, accuracy: 0.25)
    }

    /// WHOOP 4.0-like data (no strap envelope): the night is found, the film is not.
    func testWithoutStrapEnvelope() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -3.5, kind: .active, noBand: true),
            Block(from: -3.5, to: -1.6, kind: .quietWake, hr: 64, noBand: true),
            Block(from: -1.6, to: -0.5, kind: .active, noBand: true),
            Block(from: -0.5, to: 7.0, kind: .sleep, noBand: true),
            Block(from: 7.0, to: 23, kind: .active, noBand: true),
        ])
        let d = compute(date, rec)
        describe("no-band", d, day0)
        XCTAssertEqual(Double(d.sleep!.start - day0) / 3600, -0.5, accuracy: 0.25)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 7.0, accuracy: 0.25)
    }

    /// A late sleeper (02:31 → 08:24, as on the wearer's own WHOOP night).
    func testLateNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: 2.52, kind: .active),
            Block(from: 2.52, to: 8.4, kind: .sleep),
            Block(from: 8.4, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("late", d, day0)
        XCTAssertEqual(Double(d.sleep!.start - day0) / 3600, 2.52, accuracy: 0.2)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 8.4, accuracy: 0.2)
        XCTAssertEqual(d.sleep!.inBedSec / 60, 353, accuracy: 15)
    }

    /// The strap was not worn at night; an afternoon nap must not become "the night".
    func testNapWithoutANight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: 8, to: 14, kind: .active),
            Block(from: 14, to: 14.75, kind: .sleep),
            Block(from: 14.75, to: 23, kind: .active),
        ])
        let d = compute(date, rec)
        describe("nap-only", d, day0)
        XCTAssertNil(d.sleep)
        XCTAssertEqual(d.naps.count, 1)
        XCTAssertNil(d.recovery)
    }

    /// Computed while the night is still going on (03:00): a partial night, no crash, and the
    /// full night once the rest has synced.
    func testNightInProgressThenComplete() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        let partial = compute(date, rec.filter { $0.ts < day0 + 3 * 3600 }, nowHour: 3)
        describe("in-progress", partial, day0)
        let full = compute(date, rec)
        XCTAssertEqual(Double(full.sleep!.end - day0) / 3600, 7.0, accuracy: 0.25)
        if let p = partial.sleep { XCTAssertLessThanOrEqual(p.end, day0 + 3 * 3600 + 1) }
    }
    /// A strap whose envelope never leaves "wake" (some firmware): the night is still found.
    func testDeadStrapEnvelopeDoesNotHideTheNight() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active, band: 0),
            Block(from: -0.5, to: 7.0, kind: .sleep, band: 0),
            Block(from: 7.0, to: 14, kind: .active, band: 0),
            Block(from: 14, to: 14.75, kind: .sleep, band: 0),
            Block(from: 14.75, to: 23, kind: .active, band: 0),
        ])
        let d = compute(date, rec)
        describe("dead-band", d, day0)
        XCTAssertEqual(Double(d.sleep!.start - day0) / 3600, -0.5, accuracy: 0.25)
        XCTAssertEqual(Double(d.sleep!.end - day0) / 3600, 7.0, accuracy: 0.25)
        XCTAssertEqual(d.naps.count, 1)
    }

    /// The wearer's own times replace the detected night.
    func testManualSleepTimes() {
        let date = "2026-10-05"
        let day0 = DayKey.startUnix(date)!
        let rec = Self.record(day0: day0, [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active),
        ])
        var inputs = DayInputs(date: date, samples: rec, profile: UserProfile(), history: [], now: day0 + 36 * 3600)
        inputs.forcedSleep = (day0 + 3600, day0 + 6 * 3600)
        let d = DayEngine.compute(inputs)
        describe("manual", d, day0)
        XCTAssertEqual(d.sleep!.start, day0 + 3600)
        XCTAssertEqual(d.sleep!.end, day0 + 6 * 3600)
        XCTAssertTrue(d.naps.isEmpty)
        XCTAssertNotNil(d.sleep!.hrv)
    }
}
