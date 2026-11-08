import Foundation
import SwiftUI
import Combine
import BackgroundTasks
import UserNotifications

/// Persistent user settings (UserDefaults, JSON).
struct AppSettings: Codable, Equatable {
    var profile = UserProfile()
    var dashboard: [DashboardMetric] = DashboardMetric.defaultSelection
    var onboardingDone = false
    var demoMode = false
    var alarmEnabled = false
    var alarmMinute = 7 * 60
    var backgroundSync = true
    var continuousHR = false
    var stepCalibration = 1.0
    var rawRetentionDays = 120
}

/// Central app model: settings, computed days, recompute pipeline. Main-actor UI state; the
/// heavy work runs on `analyticsQueue`.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: AppSettings { didSet { saveSettings() } }
    @Published private(set) var days: [String: DayMetrics] = [:]
    @Published var selectedDate: String = DayKey.today()
    @Published private(set) var computing = false
    @Published private(set) var userActivities: [ActivityRecord] = []
    @Published var liveSession: LiveSession?

    let strap = StrapManager.shared
    private let analyticsQueue = DispatchQueue(label: "woop.analytics", qos: .utility)
    private var demoSamples: [HistorySample] = []
    /// Days computed on the phone from strap data.
    private var computedDays: [String: DayMetrics] = [:]
    /// Days imported from the official WHOOP export (WHOOP's own scores).
    private(set) var importedDays: [String: DayMetrics] = [:]
    private var recomputeDeadline: Date?
    private var recomputeToken = 0
    /// A recompute requested while one was running: `.some(nil)` = full, `.some(n)` = last n days.
    private var pendingRecompute: Int?? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?

    private static let settingsKey = "woop.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else {
            settings = AppSettings()
        }
        if let data = UserDefaults.standard.data(forKey: "woop.live.session"),
           let s = try? JSONDecoder().decode(LiveSession.self, from: data) {
            liveSession = s
        }
    }

    /// Screen requested by the `-woopScreen <name>` launch argument (CI screenshots).
    let launchScreen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-woopScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    func start() {
        if ProcessInfo.processInfo.arguments.contains("-woopDemo") {
            if settings.profile.firstName.isEmpty {
                settings.profile.firstName = "Paul-Louis"
                settings.profile.lastName = "R"
            }
            settings.onboardingDone = true
            settings.demoMode = true
        }
        strap.onHistoryCommitted = { [weak self] _, _ in
            // Mid-transfer: rescore at most every 90 s; the end of the drain triggers a final pass.
            Task { @MainActor in self?.scheduleRecompute(delay: 90) }
        }
        strap.onDrainComplete = { [weak self] in
            Task { @MainActor in self?.scheduleRecompute(delay: 1) }
        }
        if settings.demoMode {
            enableDemo()
        } else {
            loadStored()
            recompute(daysBack: 3)
        }
        if settings.onboardingDone && !settings.demoMode {
            strap.start()
            strap.setBackgroundLive(settings.continuousHR)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute(daysBack: 1) }
        }
        if liveSession != nil { strap.setLiveWanted(true) }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    // MARK: Data access

    var today: String { DayKey.today() }

    func day(_ key: String) -> DayMetrics? { days[key] }

    var selected: DayMetrics { days[selectedDate] ?? .empty(selectedDate) }

    var isToday: Bool { selectedDate == today }

    /// Days ascending, up to and including `key`, at most `count`.
    func history(upTo key: String, count: Int) -> [DayMetrics] {
        days.values.filter { $0.date <= key }.sorted { $0.date < $1.date }.suffix(count).map { $0 }
    }

    func loadStored() {
        let all = Database.shared.allDays().filter { $0.algoVersion == DayMetrics.algoVersion }
        var map: [String: DayMetrics] = [:]
        for d in all { map[d.date] = d }
        computedDays = map
        var imp: [String: DayMetrics] = [:]
        for d in Database.shared.importedDays() { imp[d.date] = d }
        importedDays = imp
        rebuildMerged()
        reloadActivities()
    }

    /// Publish computed days with WHOOP-imported scores layered on top.
    func rebuildMerged() {
        days = Self.merge(computedDays, importedDays)
    }

    nonisolated static func merge(_ computed: [String: DayMetrics], _ imported: [String: DayMetrics]) -> [String: DayMetrics] {
        var out: [String: DayMetrics] = [:]
        for k in Set(computed.keys).union(imported.keys) {
            if let m = DayMetrics.merged(computed: computed[k], imported: imported[k]) { out[k] = m }
        }
        return out
    }

    func reloadActivities() {
        if settings.demoMode { return }
        let now = Int(Date().timeIntervalSince1970)
        userActivities = Database.shared.activities(from: now - 400 * 86400, to: now + 86400)
    }

    // MARK: Recompute

    /// Debounced full recompute; a sooner request replaces a later pending one.
    func scheduleRecompute(delay: TimeInterval) {
        let deadline = Date().addingTimeInterval(delay)
        if let pending = recomputeDeadline, pending <= deadline { return }
        recomputeDeadline = deadline
        recomputeToken += 1
        let token = recomputeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.recomputeToken == token else { return }
            self.recomputeDeadline = nil
            self.recompute(daysBack: nil)
        }
    }

    /// Recompute days with data. `daysBack == nil` → every day since the oldest unsynced change
    /// (bounded to 45 days), otherwise the last N days.
    func recompute(daysBack: Int?, completion: (() -> Void)? = nil) {
        guard !computing else {
            // Remember the widest request and run it right after the current pass.
            switch (pendingRecompute, daysBack) {
            case (.none, _): pendingRecompute = .some(daysBack)
            case (.some(.some(let a)), .some(let b)): pendingRecompute = .some(max(a, b))
            default: pendingRecompute = .some(nil)
            }
            completion?()
            return
        }
        computing = true
        let settings = self.settings
        let existing = computedDays
        let imported = settings.demoMode ? [:] : importedDays
        let demo = settings.demoMode ? demoSamples : nil
        let activities = userActivities
        analyticsQueue.async {
            let now = Int(Date().timeIntervalSince1970)
            let today = DayKey.today()
            var oldest: String
            if let demo, let first = demo.first {
                oldest = DayKey.key(unix: first.ts)
            } else {
                let stats = Database.shared.sampleStats()
                guard let o = stats.oldest else {
                    Task { @MainActor in
                        self.computing = false
                        completion?()
                        self.runPendingRecompute()
                    }
                    return
                }
                oldest = DayKey.key(unix: o)
            }
            var startKey: String
            if let n = daysBack {
                startKey = DayKey.adding(-(n - 1), to: today)
            } else {
                // Everything missing or stale, at most 45 days back.
                let floor = DayKey.adding(-44, to: today)
                var k = max(oldest, floor)
                while k < today, let d = existing[k], d.algoVersion == DayMetrics.algoVersion,
                      d.computedAt > (DayKey.startUnix(DayKey.adding(2, to: k)) ?? 0) {
                    k = DayKey.adding(1, to: k)
                }
                startKey = DayKey.adding(-1, to: k)
            }
            if startKey < oldest { startKey = oldest }
            var computed: [String: DayMetrics] = existing
            var key = startKey
            while key <= today {
                guard let ds = DayKey.startUnix(key) else { break }
                let from = ds - 13 * 3600
                let to = min(now, ds + 86400 + 13 * 3600)
                let samples: [HistorySample]
                if let demo {
                    samples = Array(TimeIndex.slice(demo, from: from, to: to))
                } else {
                    samples = Database.shared.samples(from: from, to: to)
                }
                let floorKey = DayKey.adding(-60, to: key)
                let hist = Self.merge(computed.filter { $0.key < key && $0.key >= floorKey },
                                      imported.filter { $0.key < key && $0.key >= floorKey })
                    .values.sorted { $0.date < $1.date }
                var m = DayEngine.compute(DayInputs(date: key, samples: samples, profile: settings.profile,
                                                    history: Array(hist), userActivities: activities, now: now))
                if let steps = m.steps { m.steps = Int((Double(steps) / max(0.5, settings.stepCalibration)).rounded()) }
                if m.hasData || m.calories != nil {
                    computed[key] = m
                    if demo == nil { Database.shared.saveDay(m) }
                }
                key = DayKey.adding(1, to: key)
            }
            let result = computed
            Task { @MainActor in
                self.computedDays = result
                self.rebuildMerged()
                self.computing = false
                self.notifyRecoveryIfNeeded()
                completion?()
                self.runPendingRecompute()
            }
        }
    }

    private func runPendingRecompute() {
        guard let pending = pendingRecompute else { return }
        pendingRecompute = nil
        recompute(daysBack: pending)
    }

    func recomputeAll() {
        guard !computing else { return }
        computedDays = [:]
        rebuildMerged()
        recompute(daysBack: 45)
    }

    // MARK: Notifications

    /// Once per day, when this morning's recovery first becomes available, post it (like WHOOP).
    func notifyRecoveryIfNeeded() {
        guard !settings.demoMode, let d = days[today], let r = d.recovery, let s = d.sleep else { return }
        let now = Int(Date().timeIntervalSince1970)
        guard now - s.end < 8 * 3600 else { return }
        let key = "woop.notified.recovery"
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        let content = UNMutableNotificationContent()
        let zone: String
        switch Recovery.zone(r) {
        case .green: zone = "🟢 prêt pour un effort important"
        case .yellow: zone = "🟡 un effort modéré est adapté"
        case .red: zone = "🔴 privilégie la récupération"
        }
        content.title = "Récupération : \(Int(r)) %"
        var body = zone
        if let p = d.sleepPerformance { body += " · Sommeil \(Int(p)) %" }
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "recovery-\(today)", content: content, trigger: nil))
    }

    // MARK: Background refresh

    static let refreshTaskID = "com.ramphortpl.woop.refresh"

    func scheduleBackgroundRefresh() {
        guard settings.backgroundSync, !settings.demoMode else { return }
        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// Runs inside iOS's background refresh window: sync the strap, then rescore today.
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        _ = await strap.syncAndWait(timeout: 22)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            recompute(daysBack: 2) { cont.resume() }
        }
    }

    // MARK: Demo

    func setDemoMode(_ on: Bool) {
        settings.demoMode = on
        if on {
            enableDemo()
        } else {
            demoSamples = []
            loadStored()
            recompute(daysBack: nil)
            if settings.onboardingDone { strap.start() }
        }
    }

    private func enableDemo() {
        computedDays = [:]
        importedDays = [:]
        rebuildMerged()
        computing = true
        analyticsQueue.async {
            let samples = DemoData.generate(days: 14)
            Task { @MainActor in
                self.demoSamples = samples
                self.userActivities = []
                self.computing = false
                self.recompute(daysBack: 14)
            }
        }
    }

    // MARK: Activities

    func addActivity(_ a: ActivityRecord) {
        if !settings.demoMode { Database.shared.saveActivity(a) }
        userActivities.append(a)
        recompute(daysBack: 2)
    }

    func deleteActivity(_ a: ActivityRecord) {
        if !settings.demoMode { Database.shared.deleteActivity(id: a.id) }
        userActivities.removeAll { $0.id == a.id }
        recompute(daysBack: 2)
    }

    // MARK: Live activity session

    func startLiveSession(sport: String) {
        let s = LiveSession(sport: sport, start: Int(Date().timeIntervalSince1970))
        liveSession = s
        persistLive()
        strap.setLiveWanted(true)
    }

    func endLiveSession(save: Bool) {
        guard let s = liveSession else { return }
        liveSession = nil
        persistLive()
        strap.setLiveWanted(false)
        let end = Int(Date().timeIntervalSince1970)
        if save, end - s.start >= 60 {
            addActivity(ActivityRecord(id: "live-\(s.start)", sport: s.sport, start: s.start, end: end, source: .live))
        }
    }

    private func persistLive() {
        if let s = liveSession, let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: "woop.live.session")
        } else {
            UserDefaults.standard.removeObject(forKey: "woop.live.session")
        }
    }

    // MARK: Derived helpers

    /// Consecutive days (ending today or yesterday) with at least 1 h of wear.
    var streak: Int {
        var n = 0
        var k = today
        if (days[k]?.wornMinutes ?? 0) < 60 { k = DayKey.adding(-1, to: k) }
        while let d = days[k], d.wornMinutes >= 60 || d.sleep != nil {
            n += 1
            k = DayKey.adding(-1, to: k)
        }
        return n
    }

    /// Mean of a metric over the 30 days before `key` (excluding it).
    func baseline(_ metric: DashboardMetric, before key: String) -> Double? {
        let hist = history(upTo: DayKey.adding(-1, to: key), count: 30)
        let vals = hist.compactMap { metric.value(day: $0, state: self) }
        return Stats.mean(vals)
    }

    /// Typical wake time (minutes after midnight) from the last 7 nights.
    var typicalWakeMinute: Int {
        let ends = history(upTo: today, count: 7).compactMap { $0.sleep?.end }.map { DayKey.minuteOfDay(unix: $0) }
        guard ends.count >= 3, let m = Stats.median(ends.map(Double.init)) else { return settings.profile.usualWakeMinute }
        return Int(m)
    }

    var typicalEfficiency: Double {
        let e = history(upTo: today, count: 14).compactMap { $0.sleep?.efficiency }
        return Stats.mean(e) ?? 0.9
    }

    /// Recommended bedtime for tonight (before the alarm, or the usual wake time).
    var recommendedBedtime: Date? {
        guard let need = days[today]?.tonightNeedSec ?? days[DayKey.adding(-1, to: today)]?.tonightNeedSec else { return nil }
        let wakeMinute = settings.alarmEnabled ? settings.alarmMinute : typicalWakeMinute
        let cal = DayKey.calendar
        var wake = cal.date(bySettingHour: wakeMinute / 60, minute: wakeMinute % 60, second: 0, of: Date()) ?? Date()
        if wake < Date().addingTimeInterval(3600) { wake = cal.date(byAdding: .day, value: 1, to: wake) ?? wake }
        return SleepCoach.recommendedBedtime(wake: wake, needSec: need, efficiency: typicalEfficiency)
    }

    func applyAlarm() {
        guard settings.alarmEnabled else {
            strap.setAlarm(nil)
            return
        }
        let cal = DayKey.calendar
        var d = cal.date(bySettingHour: settings.alarmMinute / 60, minute: settings.alarmMinute % 60, second: 0, of: Date()) ?? Date()
        if d <= Date() { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        strap.setAlarm(d)
    }
}

/// An activity being recorded live ("Commencer une activité").
struct LiveSession: Codable, Equatable {
    var sport: String
    var start: Int
}
