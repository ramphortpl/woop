import XCTest
@testable import WoopCore

final class NotificationTests: XCTestCase {
    let today = "2026-11-08"
    var t0: Int { DayKey.startUnix(today)! }

    func day(_ key: String) -> DayMetrics { DayMetrics(date: key) }

    func initializedLog() -> NotifyLog {
        var log = NotifyLog()
        log.initialized = true
        return log
    }

    func autoActivity(start: Int, minutes: Int, sport: String = "course") -> ActivityRecord {
        var a = ActivityRecord(id: "auto-\(start)", sport: sport, start: start, end: start + minutes * 60, source: .auto)
        a.strain = 11.4
        a.calories = 612
        a.avgHR = 151
        return a
    }

    func testFirstRunIsSilent() {
        var d = day(today)
        d.activities = [autoActivity(start: t0 + 9 * 3600, minutes: 40)]
        var log = NotifyLog()
        let c = NotifyContext(days: [today: d], today: today, now: t0 + 12 * 3600, dataEnd: t0 + 12 * 3600)
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
        XCTAssertTrue(log.initialized)
        // The same activity is not announced later either.
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
    }

    func testActivityNotifiedOnceItIsOver() {
        let start = t0 + 17 * 3600
        var d = day(today)
        d.activities = [autoActivity(start: start, minutes: 45)]
        var log = initializedLog()
        // Data stops right at the end: maybe still going, wait.
        var c = NotifyContext(days: [today: d], today: today, now: start + 50 * 60, dataEnd: start + 46 * 60)
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
        // Ten calm minutes later: announced, with the confirm / change actions.
        c.dataEnd = start + 57 * 60
        c.now = start + 60 * 60
        let n = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.kind, .activity)
        XCTAssertEqual(n.first?.title, "Activité détectée : Course à pied")
        XCTAssertTrue(n.first?.body.contains("Effort 11,4") ?? false)
        XCTAssertTrue(n.first?.activityActions ?? false)
        XCTAssertEqual(n.first?.route, "activity:\(today):auto-\(start)")
        // A rescoring that shifts the start by a minute is still the same activity.
        d.activities = [autoActivity(start: start + 60, minutes: 44)]
        c.days = [today: d]
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
    }

    func testLiveActivityAndOldActivities() {
        var live = ActivityRecord(id: "live-1", sport: "padel", start: t0 + 18 * 3600, end: t0 + 19 * 3600, source: .live)
        live.strain = 9.8
        let old = autoActivity(start: t0 + 1 * 3600, minutes: 30) // ended long ago
        var d = day(today)
        d.activities = [old, live]
        var log = initializedLog()
        let c = NotifyContext(days: [today: d], today: today, now: t0 + 19 * 3600 + 120, dataEnd: t0 + 19 * 3600 + 60)
        let n = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(n.map(\.title), ["Activité enregistrée : Padel"])
        XCTAssertFalse(n[0].activityActions)
    }

    func testMorningRecoveryAfterWaking() {
        var d = day(today)
        d.sleep = SleepSession(start: t0 - 3600, end: t0 + 7 * 3600, lightSec: 14400, deepSec: 5400, remSec: 6000)
        d.recovery = 45
        d.sleepPerformance = 76
        var log = initializedLog()
        // Still in bed (no data after the last sleep minute): nothing yet.
        var c = NotifyContext(days: [today: d], today: today, now: t0 + 7 * 3600 + 300, dataEnd: t0 + 7 * 3600 + 120, firstName: "Paul-Louis")
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
        c.now = t0 + 7 * 3600 + 1800
        c.dataEnd = t0 + 7 * 3600 + 1500
        let n = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].title, "🟡 Récupération : 45 %")
        XCTAssertTrue(n[0].body.hasPrefix("Bonjour Paul-Louis !"))
        XCTAssertTrue(n[0].body.contains("Effort conseillé : 9,0–13,5"))
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty, "once a day")
    }

    /// Awake at 03:00 is not the morning: the night is not announced after 20 minutes — the
    /// wearer may go back to sleep — unless they are clearly up and about.
    func testNightAwakeningIsNotAnnouncedAsTheMorning() {
        var d = day(today)
        d.sleep = SleepSession(start: t0 - 3600, end: t0 + 3 * 3600, lightSec: 7200, deepSec: 3600, remSec: 2400)
        d.recovery = 38
        d.sleepPerformance = 44
        d.steps = 60
        var log = initializedLog()
        var c = NotifyContext(days: [today: d], today: today, now: t0 + 3 * 3600 + 1800, dataEnd: t0 + 3 * 3600 + 1500)
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty, "25 minutes awake at 03:00: wait")
        // Up for good (a thousand steps): the night is over.
        var up = d
        up.steps = 1400
        var logUp = initializedLog()
        c.days = [today: up]
        XCTAssertEqual(NotificationPlanner.plan(c, log: &logUp).map(\.kind), [.recovery])
        // Still quiet 95 minutes later: announced as it stands.
        c.days = [today: d]
        c.now = t0 + 3 * 3600 + 96 * 60
        c.dataEnd = t0 + 3 * 3600 + 95 * 60
        XCTAssertEqual(NotificationPlanner.plan(c, log: &log).map(\.kind), [.recovery])
        XCTAssertEqual(log.sleepEndNotified, t0 + 3 * 3600)
    }

    /// The night was announced, then the wearer went back to sleep: the same night, longer, is
    /// announced once more (and only once).
    func testExtendedNightIsAnnouncedAgain() {
        var d = day(today)
        d.sleep = SleepSession(start: t0 - 3600, end: t0 + 3 * 3600, lightSec: 7200, deepSec: 3600, remSec: 2400)
        d.recovery = 38
        d.sleepPerformance = 44
        var log = initializedLog()
        var c = NotifyContext(days: [today: d], today: today, now: t0 + 5 * 3600, dataEnd: t0 + 5 * 3600 - 60)
        XCTAssertEqual(NotificationPlanner.plan(c, log: &log).map(\.kind), [.recovery])
        // Back to sleep 05:00 → 07:30; the rescored night now runs to 07:30.
        d.sleep = SleepSession(start: t0 - 3600, end: t0 + 7 * 3600 + 1800, awakeSec: 7200, lightSec: 12600, deepSec: 5400, remSec: 5400)
        d.recovery = 61
        d.sleepPerformance = 82
        c.days = [today: d]
        c.now = t0 + 8 * 3600
        c.dataEnd = t0 + 8 * 3600 - 60
        let n = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "Nuit mise à jour")
        XCTAssertTrue(n.first?.body.contains("Retour au sommeil pris en compte") ?? false)
        XCTAssertTrue(n.first?.body.contains("Récupération : 61 %") ?? false)
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty, "once")
        // A rescoring that moves the end by a few minutes says nothing.
        d.sleep?.end += 300
        c.days = [today: d]
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
    }

    func testSleepWhileCalibratingAndHealthMonitor() {
        var hist: [String: DayMetrics] = [:]
        for i in 1...10 {
            var h = day(DayKey.adding(-i, to: today))
            h.rhr = 52 + Double(i % 3)
            h.respRate = 14.5 + Double(i % 2) * 0.2
            hist[h.date] = h
        }
        var d = day(today)
        d.sleep = SleepSession(start: t0 - 3600, end: t0 + 7 * 3600, lightSec: 14400, deepSec: 5400, remSec: 6000)
        d.sleepPerformance = 88
        d.calibrationNights = 2
        d.rhr = 63
        d.respRate = 17.2
        hist[today] = d
        var log = initializedLog()
        let c = NotifyContext(days: hist, today: today, now: t0 + 8 * 3600, dataEnd: t0 + 8 * 3600)
        let n = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(n.map(\.kind), [.sleep, .health])
        XCTAssertTrue(n[0].body.contains("Calibrage de ta récupération : 2/4"))
        XCTAssertTrue(n[1].body.contains("FC au repos élevée"))
    }

    func testStrainCoach() {
        var d = day(today)
        d.recovery = 70
        d.strain = 14.0
        var log = initializedLog()
        var c = NotifyContext(days: [today: d], today: today, now: t0 + 15 * 3600, dataEnd: t0 + 15 * 3600)
        XCTAssertEqual(NotificationPlanner.plan(c, log: &log).map(\.kind), [.strainTarget])
        XCTAssertTrue(NotificationPlanner.plan(c, log: &log).isEmpty)
        d.strain = 19.6
        c.days = [today: d]
        c.bedtime = t0 + 22 * 3600 + 40 * 60
        let over = NotificationPlanner.plan(c, log: &log)
        XCTAssertEqual(over.map(\.kind), [.strainOver])
        XCTAssertTrue(over[0].body.contains("22:40"))
        // Not at night.
        var night = initializedLog()
        c.now = t0 + 23 * 3600 + 30 * 60
        XCTAssertTrue(NotificationPlanner.plan(c, log: &night).isEmpty)
    }

    func testBatteryCycle() {
        var log = NotifyLog()
        let p = NotifyPrefs()
        XCTAssertNil(NotificationPlanner.battery(level: 55, charging: false, prefs: p, log: &log))
        XCTAssertEqual(NotificationPlanner.battery(level: 19, charging: false, prefs: p, log: &log)?.title, "Batterie du bracelet faible : 19 %")
        XCTAssertNil(NotificationPlanner.battery(level: 18, charging: false, prefs: p, log: &log))
        XCTAssertEqual(NotificationPlanner.battery(level: 9, charging: false, prefs: p, log: &log)?.title, "Batterie du bracelet très faible : 9 %")
        XCTAssertNil(NotificationPlanner.battery(level: 30, charging: true, prefs: p, log: &log))
        XCTAssertEqual(NotificationPlanner.battery(level: 100, charging: true, prefs: p, log: &log)?.title, "Bracelet rechargé")
        XCTAssertNil(NotificationPlanner.battery(level: 100, charging: true, prefs: p, log: &log))
        XCTAssertNotNil(NotificationPlanner.battery(level: 20, charging: false, prefs: p, log: &log))
    }

    func testWeeklySummary() {
        var days: [String: DayMetrics] = [:]
        for i in 1...7 {
            var d = day(DayKey.adding(-i, to: "2026-11-09"))
            d.recovery = 60
            d.strain = 10
            d.sleep = SleepSession(start: 0, end: 30000, lightSec: 14400, deepSec: 6000, remSec: 6000)
            d.sleepPerformance = 85
            days[d.date] = d
        }
        let w = NotificationPlanner.weekly(days: days, monday: "2026-11-09")
        XCTAssertEqual(w?.body, "Récupération moy. 60 % · Sommeil moy. 7:20 (85 %) · Effort moy. 10,0.")
        XCTAssertNil(NotificationPlanner.weekly(days: [:], monday: "2026-11-09"))
    }

    func testPrefsDecodeOldSettings() throws {
        let p = try JSONDecoder().decode(NotifyPrefs.self, from: Data(#"{"activities":false}"#.utf8))
        XCTAssertFalse(p.activities)
        XCTAssertTrue(p.recovery)
        XCTAssertEqual(p.bedtimeLeadMinutes, 30)
    }
}
