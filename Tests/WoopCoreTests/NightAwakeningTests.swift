import XCTest
@testable import WoopCore

/// "I wake up during my night, and when I fall back asleep the rest is booked as a nap."
/// Every return to sleep during the night must stay inside the SAME night; a nap is a sleep the
/// wearer takes once the day has started.
final class NightAwakeningTests: XCTestCase {
    typealias Block = SleepScenarioTests.Block

    let date = "2026-10-05"
    var day0: Int { DayKey.startUnix(date)! }

    func compute(_ blocks: [Block], date: String? = nil, history: [DayMetrics] = [], nowHour: Double = 36) -> DayMetrics {
        let rec = SleepScenarioTests.record(day0: day0, blocks)
        let key = date ?? self.date
        return DayEngine.compute(DayInputs(date: key, samples: rec, profile: UserProfile(), history: history,
                                           now: DayKey.startUnix(key)! + Int(nowHour * 3600)))
    }

    func hours(_ unix: Int) -> Double { Double(unix - day0) / 3600 }

    func show(_ tag: String, _ d: DayMetrics) {
        func hm(_ u: Int) -> String {
            let m = (((u - day0) / 60) % 1440 + 1440) % 1440
            return String(format: "%02d:%02d", m / 60, m % 60)
        }
        let naps = d.naps.map { "\(hm($0.start))-\(hm($0.end)) (\($0.asleepSec / 60)m)" }
        if let s = d.sleep {
            print("\(tag): \(hm(s.start))→\(hm(s.end)) asleep=\(s.asleepSec / 60)m awake=\(s.awakeSec / 60)m eff=\(Int(s.efficiency * 100)) naps=\(naps)")
        } else {
            print("\(tag): no sleep; naps=\(naps)")
        }
    }

    /// Nights of a wearer who sleeps `bed` → `wake` (hours since midnight), for the habit.
    func pastNights(bed: Double, wake: Double, count: Int = 8) -> [DayMetrics] {
        (1...count).reversed().map { k in
            let key = DayKey.adding(-k, to: date)
            let d0 = DayKey.startUnix(key)!
            var d = DayMetrics(date: key)
            d.sleep = SleepSession(start: d0 + Int(bed * 3600), end: d0 + Int(wake * 3600))
            return d
        }
    }

    // MARK: Returns to sleep that are the same night

    /// Asleep 23:30 → 02:30, up for two hours, asleep again 04:30 → 08:00: one night.
    func testTwoHourAwakeningStaysOneNight() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.5, kind: .sleep),
            Block(from: 2.5, to: 4.5, kind: .active, steps: 2),
            Block(from: 4.5, to: 8.0, kind: .sleep),
            Block(from: 8.0, to: 23, kind: .active, steps: 8),
        ])
        show("2h-awake", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -0.5, accuracy: 0.25)
        XCTAssertEqual(hours(s.end), 8.0, accuracy: 0.25)
        XCTAssertGreaterThan(s.awakeSec, 110 * 60)
        XCTAssertGreaterThan(s.asleepSec, Int(5.8 * 3600))
        XCTAssertTrue(d.naps.isEmpty, "the second half of the night is not a nap")
    }

    /// The first half is the SHORTER one: it must not become a "nap at 23:00" either.
    func testShortFirstHalfIsNotANap() {
        let d = compute([
            Block(from: -10, to: -1, kind: .active),
            Block(from: -1, to: 1, kind: .sleep),
            Block(from: 1, to: 3.2, kind: .upAtNight),
            Block(from: 3.2, to: 8.5, kind: .sleep),
            Block(from: 8.5, to: 23, kind: .active, steps: 8),
        ])
        show("short-first-half", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -1, accuracy: 0.25)
        XCTAssertEqual(hours(s.end), 8.5, accuracy: 0.25)
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Two hours awake, then only 45 minutes of sleep before getting up: still the night.
    func testShortReturnToSleepAfterALongAwakening() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 4.0, kind: .sleep),
            Block(from: 4.0, to: 6.0, kind: .active, steps: 1),
            Block(from: 6.0, to: 6.75, kind: .sleep),
            Block(from: 6.75, to: 23, kind: .active, steps: 8),
        ])
        show("short-return", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.end), 6.75, accuracy: 0.25)
        XCTAssertGreaterThan(s.asleepSec, Int(4.7 * 3600))
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Dozing off again three times before getting up (each under an hour).
    func testSeveralShortReturnsToSleep() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 5.0, kind: .sleep),
            Block(from: 5.0, to: 5.3, kind: .active),
            Block(from: 5.3, to: 5.9, kind: .sleep),
            Block(from: 5.9, to: 6.2, kind: .active),
            Block(from: 6.2, to: 6.8, kind: .sleep),
            Block(from: 6.8, to: 7.1, kind: .active),
            Block(from: 7.1, to: 7.6, kind: .sleep),
            Block(from: 7.6, to: 23, kind: .active, steps: 8),
        ])
        show("several-returns", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -0.5, accuracy: 0.25)
        XCTAssertEqual(hours(s.end), 7.6, accuracy: 0.25)
        XCTAssertGreaterThan(s.asleepSec, Int(6.3 * 3600))
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Fell asleep at 23:00 for 50 minutes, awake two hours, then the rest of the night.
    func testShortFirstSleepThenLongAwakening() {
        let d = compute([
            Block(from: -10, to: -1, kind: .active),
            Block(from: -1, to: -0.17, kind: .sleep),
            Block(from: -0.17, to: 1.8, kind: .active, steps: 2),
            Block(from: 1.8, to: 7.5, kind: .sleep),
            Block(from: 7.5, to: 23, kind: .active, steps: 8),
        ])
        show("short-first-sleep", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -1, accuracy: 0.3)
        XCTAssertEqual(hours(s.end), 7.5, accuracy: 0.25)
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Four hours of insomnia in the middle of the night: one (bad) night, no nap.
    func testLongInsomniaIsOneNight() {
        let d = compute([
            Block(from: -10, to: -1, kind: .active),
            Block(from: -1, to: 1, kind: .sleep),
            Block(from: 1, to: 5, kind: .active, steps: 1),
            Block(from: 5, to: 8, kind: .sleep),
            Block(from: 8, to: 23, kind: .active, steps: 8),
        ])
        show("insomnia", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -1, accuracy: 0.25)
        XCTAssertEqual(hours(s.end), 8, accuracy: 0.25)
        XCTAssertGreaterThan(s.awakeSec, Int(3.7 * 3600))
        XCTAssertLessThan(s.efficiency, 0.65)
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// A late sleeper (03:00 → 10:30) who wakes at 09:00 and sleeps again 11:10 → 13:00: the
    /// app has learned that this is still their night.
    func testLateSleeperReturnToSleepUsesTheLearnedHabit() {
        let blocks = [
            Block(from: -8, to: 3, kind: .active),
            Block(from: 3, to: 9, kind: .sleep),
            Block(from: 9, to: 11.17, kind: .active, steps: 2),
            Block(from: 11.17, to: 13, kind: .sleep),
            Block(from: 13, to: 23, kind: .active, steps: 8),
        ]
        let learned = compute(blocks, history: pastNights(bed: 3, wake: 10.5))
        show("late-sleeper", learned)
        XCTAssertEqual(hours(learned.sleep!.start), 3, accuracy: 0.25)
        XCTAssertEqual(hours(learned.sleep!.end), 13, accuracy: 0.25)
        XCTAssertTrue(learned.naps.isEmpty)
    }

    /// The time awake inside the night counts toward the day's effort like any waking time.
    func testAwakeTimeInsideTheNightCountsAsAwake() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.5, kind: .sleep),
            Block(from: 2.5, to: 4.5, kind: .active, steps: 2),
            Block(from: 4.5, to: 8.0, kind: .sleep),
            Block(from: 8.0, to: 23, kind: .active, steps: 8),
        ])
        // 15 h of day + 2 h awake in the night carry a heart rate outside sleep.
        XCTAssertGreaterThan(d.zoneSeconds.reduce(0, +), Int(16.6 * 3600))
    }

    /// Up at 03:00, pacing the flat (1 200 steps), a doze on the sofa, back to bed at 04:25:
    /// the doze must not cut the night in two — it is one night with an awakening in it.
    func testADozeDuringAnAwakeningDoesNotSplitTheNight() {
        let d = compute([
            Block(from: -10, to: -1, kind: .active),
            Block(from: -1, to: 3, kind: .sleep),
            Block(from: 3, to: 3.67, kind: .active, steps: 30),
            Block(from: 3.67, to: 4.1, kind: .sleep),
            Block(from: 4.1, to: 4.4, kind: .active, steps: 5),
            Block(from: 4.4, to: 7.5, kind: .sleep),
            Block(from: 7.5, to: 23, kind: .active, steps: 8),
        ])
        show("doze-in-awakening", d)
        let s = d.sleep!
        XCTAssertEqual(hours(s.start), -1, accuracy: 0.25)
        XCTAssertEqual(hours(s.end), 7.5, accuracy: 0.25)
        XCTAssertGreaterThan(s.asleepSec, Int(6.8 * 3600))
        XCTAssertTrue(d.naps.isEmpty)
    }

    /// Same nights on a strap without its own sleep/wake state (WHOOP 4.0, or an envelope that
    /// never reports "asleep"): the heart rate against the sleeping level decides alone.
    func testReturnsToSleepWithoutTheStrapEnvelope() {
        let long = compute([
            Block(from: -10, to: -0.5, kind: .active, noBand: true),
            Block(from: -0.5, to: 2.5, kind: .sleep, noBand: true),
            Block(from: 2.5, to: 4.5, kind: .active, noBand: true, steps: 2),
            Block(from: 4.5, to: 8.0, kind: .sleep, noBand: true),
            Block(from: 8.0, to: 23, kind: .active, noBand: true, steps: 8),
        ])
        show("no-band 2h-awake", long)
        XCTAssertEqual(hours(long.sleep!.start), -0.5, accuracy: 0.25)
        XCTAssertEqual(hours(long.sleep!.end), 8.0, accuracy: 0.25)
        XCTAssertTrue(long.naps.isEmpty)
        let short = compute([
            Block(from: -10, to: -0.5, kind: .active, band: 0),
            Block(from: -0.5, to: 4.0, kind: .sleep, band: 0),
            Block(from: 4.0, to: 6.0, kind: .active, band: 0, steps: 1),
            Block(from: 6.0, to: 6.75, kind: .sleep, band: 0),
            Block(from: 6.75, to: 23, kind: .active, band: 0, steps: 8),
        ])
        show("dead-band short-return", short)
        XCTAssertEqual(hours(short.sleep!.end), 6.75, accuracy: 0.25)
        XCTAssertTrue(short.naps.isEmpty)
    }

    /// What the app shows while the night is going on: cut at the awakening when it syncs then,
    /// and whole again once the rest has arrived — never a night plus a nap.
    func testTheNightGrowsAsTheDataArrives() {
        let blocks = [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.5, kind: .sleep),
            Block(from: 2.5, to: 4.5, kind: .active, steps: 2),
            Block(from: 4.5, to: 8.0, kind: .sleep),
            Block(from: 8.0, to: 23, kind: .active, steps: 8),
        ]
        let rec = SleepScenarioTests.record(day0: day0, blocks)
        func at(_ hour: Double) -> DayMetrics {
            let now = day0 + Int(hour * 3600)
            return DayEngine.compute(DayInputs(date: date, samples: rec.filter { $0.ts < now }, profile: UserProfile(),
                                               history: [], now: now))
        }
        let awake = at(3.5)      // synced during the awakening
        show("grow@03:30", awake)
        XCTAssertEqual(hours(awake.sleep!.end), 2.5, accuracy: 0.25)
        XCTAssertTrue(awake.naps.isEmpty)
        let back = at(6.5)       // synced after two hours back asleep
        show("grow@06:30", back)
        XCTAssertEqual(hours(back.sleep!.start), -0.5, accuracy: 0.25)
        XCTAssertGreaterThan(hours(back.sleep!.end), 6.0)
        XCTAssertTrue(back.naps.isEmpty)
        let morning = at(9)
        show("grow@09:00", morning)
        XCTAssertEqual(hours(morning.sleep!.end), 8.0, accuracy: 0.25)
        XCTAssertTrue(morning.naps.isEmpty)
    }

    /// Asleep 40 minutes, awake, phone in hand at 03:20: that first sleep is not shown as a
    /// "nap at 02:30" — the night is simply not over. Once the rest has arrived it is its start.
    func testAShortFirstSleepIsNotShownAsANapWhileTheNightGoesOn() {
        let blocks = [
            Block(from: -8, to: 2.5, kind: .active, steps: 5),
            Block(from: 2.5, to: 3.17, kind: .sleep),
            Block(from: 3.17, to: 3.85, kind: .active, steps: 1),
            Block(from: 3.85, to: 9.0, kind: .sleep),
            Block(from: 9.0, to: 23, kind: .active, steps: 8),
        ]
        let rec = SleepScenarioTests.record(day0: day0, blocks)
        func at(_ hour: Double) -> DayMetrics {
            let now = day0 + Int(hour * 3600)
            return DayEngine.compute(DayInputs(date: date, samples: rec.filter { $0.ts < now }, profile: UserProfile(),
                                               history: [], now: now))
        }
        let early = at(3.5)
        show("first-sleep@03:30", early)
        XCTAssertTrue(early.naps.isEmpty, "not a nap: the night may go on")
        let full = at(12)
        show("first-sleep@12:00", full)
        XCTAssertEqual(hours(full.sleep!.start), 2.5, accuracy: 0.3)
        XCTAssertEqual(hours(full.sleep!.end), 9.0, accuracy: 0.25)
        XCTAssertTrue(full.naps.isEmpty)
    }

    /// "C'est la suite de ma nuit": a nap put back into the night by hand keeps the time
    /// between the two as time awake.
    func testANapAttachedByHandBecomesPartOfTheNight() {
        let blocks = [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 9.5, kind: .active, steps: 40),
            Block(from: 9.5, to: 10.5, kind: .sleep),
            Block(from: 10.5, to: 23, kind: .active, steps: 8),
        ]
        let auto = compute(blocks)
        XCTAssertEqual(auto.naps.count, 1)
        let rec = SleepScenarioTests.record(day0: day0, blocks)
        var inputs = DayInputs(date: date, samples: rec, profile: UserProfile(), history: [], now: day0 + 36 * 3600)
        inputs.forcedSleep = (min(auto.sleep!.start, auto.naps[0].start), max(auto.sleep!.end, auto.naps[0].end))
        let merged = DayEngine.compute(inputs)
        show("attached", merged)
        XCTAssertTrue(merged.naps.isEmpty)
        XCTAssertEqual(hours(merged.sleep!.end), 10.5, accuracy: 0.25)
        XCTAssertGreaterThan(merged.sleep!.awakeSec, 120 * 60)
        XCTAssertGreaterThan(merged.sleep!.asleepSec, auto.sleep!.asleepSec + 35 * 60)
    }

    /// The other way round: the wearer cuts the night short by hand ("my night ended at 02:30").
    /// The part left outside is not lost: it stays, as a sleep of its own.
    func testANightCutShortByHandKeepsItsOtherHalf() {
        let blocks = [
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.5, kind: .sleep),
            Block(from: 2.5, to: 4.5, kind: .active, steps: 2),
            Block(from: 4.5, to: 8.0, kind: .sleep),
            Block(from: 8.0, to: 23, kind: .active, steps: 8),
        ]
        let rec = SleepScenarioTests.record(day0: day0, blocks)
        var inputs = DayInputs(date: date, samples: rec, profile: UserProfile(), history: [], now: day0 + 36 * 3600)
        inputs.forcedSleep = (day0 - 1800, day0 + Int(2.5 * 3600))
        let d = DayEngine.compute(inputs)
        show("cut-by-hand", d)
        XCTAssertEqual(hours(d.sleep!.end), 2.5, accuracy: 0.05)
        XCTAssertEqual(d.naps.count, 1)
        XCTAssertEqual(hours(d.naps[0].start), 4.5, accuracy: 0.25)
    }

    // MARK: Sleeps that are NOT the night

    /// A doze on the sofa at 20:15, bed at 23:30: a nap (of the evening) and a night.
    func testEveningDozeIsNotTheStartOfTheNight() {
        let blocks = [
            Block(from: -10, to: -3.75, kind: .active, steps: 8),
            Block(from: -3.75, to: -3.0, kind: .sleep),
            Block(from: -3.0, to: -0.5, kind: .active, steps: 6),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 23, kind: .active, steps: 8),
        ]
        let d = compute(blocks)
        show("evening-doze", d)
        XCTAssertEqual(hours(d.sleep!.start), -0.5, accuracy: 0.25)
        let eve = compute(blocks, date: DayKey.adding(-1, to: date))
        XCTAssertEqual(eve.naps.count, 1)
    }

    /// Up at 07:00, a morning of errands (steps), back to bed 09:30 → 10:30: a nap.
    func testNapAfterTheDayHasStartedStaysANap() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.0, kind: .sleep),
            Block(from: 7.0, to: 9.5, kind: .active, steps: 40),
            Block(from: 9.5, to: 10.5, kind: .sleep),
            Block(from: 10.5, to: 23, kind: .active, steps: 8),
        ])
        show("morning-nap", d)
        XCTAssertEqual(hours(d.sleep!.end), 7.0, accuracy: 0.25)
        XCTAssertEqual(d.naps.count, 1)
    }

    /// Dozing 20 minutes on the train after getting up and walking to the station.
    func testCommuteDozeIsNotMergedIntoTheNight() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 6.0, kind: .sleep),
            Block(from: 6.0, to: 7.2, kind: .active, steps: 45),
            Block(from: 7.2, to: 7.6, kind: .sleep),
            Block(from: 7.6, to: 23, kind: .active, steps: 8),
        ])
        show("commute-doze", d)
        XCTAssertEqual(hours(d.sleep!.end), 6.0, accuracy: 0.25)
    }

    /// Up at 06:00 for a workout, back home, asleep again 08:30 → 10:00: the day had started,
    /// so that sleep is a nap although it falls "inside the night" on the clock.
    func testEarlyWorkoutThenSleepIsANap() {
        let d = compute([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 6.0, kind: .sleep),
            Block(from: 6.0, to: 6.25, kind: .active, steps: 30),
            Block(from: 6.25, to: 7.25, kind: .active, hr: 150, steps: 150),
            Block(from: 7.25, to: 8.5, kind: .active, steps: 20),
            Block(from: 8.5, to: 10.0, kind: .sleep),
            Block(from: 10.0, to: 23, kind: .active, steps: 8),
        ])
        show("early-workout", d)
        XCTAssertEqual(hours(d.sleep!.end), 6.0, accuracy: 0.25)
        XCTAssertEqual(d.naps.count, 1)
    }

    /// Without a step counter nothing says whether the wearer stayed in bed: an awakening in
    /// the night still continues the night, one at the usual wake time does not.
    func testWithoutStepCounter() {
        func noSteps(_ blocks: [Block]) -> DayMetrics {
            var rec = SleepScenarioTests.record(day0: day0, blocks)
            for i in rec.indices { rec[i].stepCounter = -1 }
            return DayEngine.compute(DayInputs(date: date, samples: rec, profile: UserProfile(), history: [],
                                               now: day0 + 36 * 3600))
        }
        let night = noSteps([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 2.5, kind: .sleep),
            Block(from: 2.5, to: 4.5, kind: .active),
            Block(from: 4.5, to: 8.0, kind: .sleep),
            Block(from: 8.0, to: 23, kind: .active),
        ])
        show("no-steps night", night)
        XCTAssertEqual(hours(night.sleep!.end), 8.0, accuracy: 0.25)
        XCTAssertTrue(night.naps.isEmpty)
        let morning = noSteps([
            Block(from: -10, to: -0.5, kind: .active),
            Block(from: -0.5, to: 7.5, kind: .sleep),
            Block(from: 7.5, to: 9.7, kind: .active),
            Block(from: 9.7, to: 11.2, kind: .sleep),
            Block(from: 11.2, to: 23, kind: .active),
        ])
        show("no-steps morning", morning)
        XCTAssertEqual(hours(morning.sleep!.end), 7.5, accuracy: 0.25)
        XCTAssertEqual(morning.naps.count, 1)
    }

    /// An afternoon nap two awake hours after a short night is still a nap.
    func testAfternoonSleepIsNeverTheNight() {
        let d = compute([
            Block(from: -10, to: 0, kind: .active),
            Block(from: 0, to: 6.0, kind: .sleep),
            Block(from: 6.0, to: 13.5, kind: .active, steps: 10),
            Block(from: 13.5, to: 15.2, kind: .sleep),
            Block(from: 15.2, to: 23, kind: .active, steps: 8),
        ])
        show("afternoon", d)
        XCTAssertEqual(hours(d.sleep!.end), 6.0, accuracy: 0.25)
        XCTAssertEqual(d.naps.count, 1)
    }

    /// Two days in a row: broken nights, an afternoon nap, an evening doze — each sleep lands
    /// on its own day, with the right label.
    func testTwoDaysOfBrokenNightsAndNaps() {
        let blocks = [
            Block(from: -34, to: -24.5, kind: .active, steps: 8),
            Block(from: -24.5, to: -21, kind: .sleep),            // 23:30 → 03:00
            Block(from: -21, to: -19.83, kind: .active, steps: 1), // 70 min awake
            Block(from: -19.83, to: -17, kind: .sleep),           // 04:10 → 07:00
            Block(from: -17, to: -10.5, kind: .active, steps: 12),
            Block(from: -10.5, to: -9.5, kind: .sleep),           // nap 13:30 → 14:30
            Block(from: -9.5, to: -3.5, kind: .active, steps: 12),
            Block(from: -3.5, to: -3.0, kind: .sleep),            // doze 20:30 → 21:00
            Block(from: -3.0, to: -0.75, kind: .active, steps: 6),
            Block(from: -0.75, to: 1.5, kind: .sleep),            // 23:15 → 01:30
            Block(from: 1.5, to: 3.17, kind: .active, steps: 2),  // 100 min awake
            Block(from: 3.17, to: 5.5, kind: .sleep),             // 03:10 → 05:30
            Block(from: 5.5, to: 6.08, kind: .active, steps: 1),  // 35 min awake
            Block(from: 6.08, to: 7.5, kind: .sleep),             // 06:05 → 07:30
            Block(from: 7.5, to: 23, kind: .active, steps: 10),
        ]
        let eve = DayKey.adding(-1, to: date)
        let first = compute(blocks, date: eve, nowHour: 60)
        show("day-1", first)
        XCTAssertEqual(hours(first.sleep!.start), -24.5, accuracy: 0.25)
        XCTAssertEqual(hours(first.sleep!.end), -17, accuracy: 0.25)
        XCTAssertGreaterThan(first.sleep!.awakeSec, 60 * 60)
        XCTAssertEqual(first.naps.count, 2)
        XCTAssertEqual(hours(first.naps[0].start), -10.5, accuracy: 0.3)
        XCTAssertEqual(hours(first.naps[1].start), -3.5, accuracy: 0.3)
        let second = compute(blocks, history: [first])
        show("day-2", second)
        XCTAssertEqual(hours(second.sleep!.start), -0.75, accuracy: 0.25)
        XCTAssertEqual(hours(second.sleep!.end), 7.5, accuracy: 0.25)
        XCTAssertGreaterThan(second.sleep!.awakeSec, 125 * 60)
        XCTAssertTrue(second.naps.isEmpty)
    }

    /// Random broken nights (2–5 pieces of sleep, awakenings of 5 min to 3 h 20, a nap some
    /// days): whatever the engine decides, the result must hang together.
    func testRandomBrokenNightsStayCoherent() {
        var rng = AnalyticsTests.Rng(state: 2026)
        for trial in 0..<8 {
            var blocks: [Block] = []
            var t = -1.5 + rng.next() * 4.5            // first onset between 22:30 and 03:00
            blocks.append(Block(from: -10, to: t, kind: .active, steps: 6))
            let pieces = 2 + Int(rng.next() * 4)
            var slept = 0.0
            for k in 0..<pieces {
                let dur = (20 + rng.next() * 220) / 60
                blocks.append(Block(from: t, to: t + dur, kind: .sleep))
                slept += dur
                t += dur
                guard k < pieces - 1 else { break }
                let gap = (5 + rng.next() * rng.next() * 195) / 60
                blocks.append(Block(from: t, to: t + gap, kind: rng.next() < 0.5 ? .active : .upAtNight,
                                    steps: rng.next() < 0.25 ? 40 : 2))
                t += gap
            }
            let nightEnd = t
            if rng.next() < 0.5, nightEnd < 12.5 {
                blocks.append(Block(from: nightEnd, to: 14, kind: .active, steps: 12))
                blocks.append(Block(from: 14, to: 15.2, kind: .sleep))
                blocks.append(Block(from: 15.2, to: 23.5, kind: .active, steps: 8))
            } else {
                blocks.append(Block(from: nightEnd, to: 23.5, kind: .active, steps: 10))
            }
            let rec = SleepScenarioTests.record(day0: day0, blocks, seed: UInt64(100 + trial))
            let d = DayEngine.compute(DayInputs(date: date, samples: rec, profile: UserProfile(), history: [],
                                                now: day0 + 36 * 3600))
            show("random-\(trial)", d)
            guard let s = d.sleep else { XCTFail("trial \(trial): no night found"); continue }
            XCTAssertLessThanOrEqual(s.asleepSec + s.awakeSec, s.inBedSec + 60, "trial \(trial)")
            XCTAssertGreaterThan(s.asleepSec, 0, "trial \(trial)")
            // Stages are ordered, inside the night, and never overlap.
            var cursor = s.start
            for seg in s.stages {
                XCTAssertGreaterThanOrEqual(seg.start, cursor, "trial \(trial)")
                XCTAssertLessThanOrEqual(seg.end, s.end, "trial \(trial)")
                cursor = seg.end
            }
            // A nap never overlaps the night, nor another nap, and ends on this day.
            var spans = [(s.start, s.end)]
            for n in d.naps {
                for sp in spans { XCTAssertFalse(n.start < sp.1 && sp.0 < n.end, "trial \(trial): overlapping sleeps") }
                spans.append((n.start, n.end))
                XCTAssertGreaterThan(n.end, day0, "trial \(trial)")
                XCTAssertLessThanOrEqual(n.end, day0 + 86400, "trial \(trial)")
            }
            // Nothing is lost: the sleeps of the day account for most of what was really slept
            // (the pieces under 15 minutes of an awakening can go either way).
            let total = Double(s.asleepSec + d.naps.reduce(0) { $0 + $1.asleepSec }) / 3600
            XCTAssertGreaterThan(total, slept * 0.6, "trial \(trial): slept \(slept) h, found \(total) h")
        }
    }

    // MARK: The usual night

    func testNightHabitIsLearnedAcrossMidnight() {
        let tz: (Int) -> Int = { _ in 0 }
        let base = 1_790_000_000 - 1_790_000_000 % 86400
        // Bedtimes 23:30, 00:30, 23:50, 00:10, 00:00 → about midnight; wake about 07:30.
        let beds: [Int] = [-1800, 1800, -600, 600, 0]
        let wakes: [Int] = [27000, 27600, 26400, 27000, 27000]
        var nights: [(start: Int, end: Int)] = []
        for k in 0..<5 {
            let midnight: Int = base + k * 86400
            nights.append((start: midnight + beds[k], end: midnight + wakes[k]))
        }
        let h = NightHabit.learn(nights, tz: tz)
        XCTAssertTrue(h.learned)
        XCTAssertEqual(SleepSpine.circularDistance(h.bedSec, 0), 0, accuracy: 600)
        XCTAssertEqual(h.wakeSec, 27000, accuracy: 600)
        XCTAssertFalse(NightHabit.learn(Array(nights.prefix(3)), tz: tz).learned)
        // 03:00 → 05:00 lies inside the night; 21:00 → 23:00 starts before it.
        XCTAssertTrue(h.covers(base + 3 * 3600, base + 5 * 3600, lead: 3600, lag: 0, tz: tz))
        XCTAssertFalse(h.covers(base - 3 * 3600, base - 3600, lead: 3600, lag: 0, tz: tz))
    }
}
