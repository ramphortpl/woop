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
    var notify = NotifyPrefs()
    /// Statistics shown on the Sommeil / Récupération / Effort screens ("MODIFIER").
    var sleepStats: [DashboardMetric] = DashboardMetric.sleepDefaults
    var recoveryStats: [DashboardMetric] = DashboardMetric.recoveryDefaults
    var strainStats: [DashboardMetric] = DashboardMetric.strainDefaults
    /// "Suivi d'itinéraire" and "Objectif d'effort" on the start-activity screen.
    var routeTracking = true
    var strainTargetOn = true
    /// Sleep times corrected by hand, per wake day (`[start, end]` unix seconds).
    var sleepEdits: [String: [Int]] = [:]
}

extension AppSettings {
    /// Every key is optional: settings saved by an older version keep the user's profile and
    /// choices, and new options take their default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        profile = (try? c.decodeIfPresent(UserProfile.self, forKey: .profile)) ?? d.profile
        dashboard = (try? c.decodeIfPresent([DashboardMetric].self, forKey: .dashboard)) ?? d.dashboard
        onboardingDone = (try? c.decodeIfPresent(Bool.self, forKey: .onboardingDone)) ?? d.onboardingDone
        demoMode = (try? c.decodeIfPresent(Bool.self, forKey: .demoMode)) ?? d.demoMode
        alarmEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .alarmEnabled)) ?? d.alarmEnabled
        alarmMinute = (try? c.decodeIfPresent(Int.self, forKey: .alarmMinute)) ?? d.alarmMinute
        backgroundSync = (try? c.decodeIfPresent(Bool.self, forKey: .backgroundSync)) ?? d.backgroundSync
        continuousHR = (try? c.decodeIfPresent(Bool.self, forKey: .continuousHR)) ?? d.continuousHR
        stepCalibration = (try? c.decodeIfPresent(Double.self, forKey: .stepCalibration)) ?? d.stepCalibration
        rawRetentionDays = (try? c.decodeIfPresent(Int.self, forKey: .rawRetentionDays)) ?? d.rawRetentionDays
        notify = (try? c.decodeIfPresent(NotifyPrefs.self, forKey: .notify)) ?? d.notify
        sleepStats = (try? c.decodeIfPresent([DashboardMetric].self, forKey: .sleepStats)) ?? d.sleepStats
        recoveryStats = (try? c.decodeIfPresent([DashboardMetric].self, forKey: .recoveryStats)) ?? d.recoveryStats
        strainStats = (try? c.decodeIfPresent([DashboardMetric].self, forKey: .strainStats)) ?? d.strainStats
        routeTracking = (try? c.decodeIfPresent(Bool.self, forKey: .routeTracking)) ?? d.routeTracking
        strainTargetOn = (try? c.decodeIfPresent(Bool.self, forKey: .strainTargetOn)) ?? d.strainTargetOn
        sleepEdits = (try? c.decodeIfPresent([String: [Int]].self, forKey: .sleepEdits)) ?? d.sleepEdits
    }
}

/// Where a tapped notification (or another screen) asks the app to go.
enum DeepLink: Equatable {
    case home
    case route(day: String, HomeRoute)
    case planner
    case tab(MainTab)
}

/// Central app model: settings, computed days, recompute pipeline. Main-actor UI state; the
/// heavy work runs on `analyticsQueue`.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: AppSettings { didSet { saveSettings() } }
    @Published private(set) var days: [String: DayMetrics] = [:] { didSet { sortedKeys = days.keys.sorted() } }
    /// `days` keys in date order (history lookups by binary search instead of sorting each time).
    private(set) var sortedKeys: [String] = []
    @Published var selectedDate: String = DayKey.today()
    @Published private(set) var computing = false
    @Published private(set) var userActivities: [ActivityRecord] = []
    @Published var liveSession: LiveSession?
    @Published var importRunning = false
    @Published var importStatusText: String?
    @Published var importOutcome: ImportOutcome?
    /// Result of the last import, also shown on the import screen.
    @Published var lastImportMessage: String?
    @Published var deepLink: DeepLink?
    /// Activity whose sport picker opens on arrival (notification "Changer de sport").
    @Published var pendingSportEdit: String?

    let strap = StrapManager.shared
    private let analyticsQueue = DispatchQueue(label: "woop.analytics", qos: .utility)
    private(set) var demoSamples: [HistorySample] = []
    /// Bumped whenever the merged days change (invalidates chart caches).
    @Published private(set) var dataVersion = 0
    /// Per-minute heart-rate ranges already loaded for charts (see AppState+Charts).
    var hrCache: [String: [HRPoint]] = [:]
    var hrCacheOrder: [String] = []
    /// Days computed on the phone from strap data.
    private var computedDays: [String: DayMetrics] = [:]
    /// Days imported from the official WHOOP export (WHOOP's own scores).
    private(set) var importedDays: [String: DayMetrics] = [:]
    /// Personal calibration learned from the WHOOP export (nil = none imported yet).
    @Published private(set) var calibration: Calibration?
    private var calibrationFitting = false
    private static let calibrationKey = "woop.calibration"
    private var recomputeDeadline: Date?
    private var recomputeToken = 0
    /// A recompute requested while one was running: `.some(nil)` = full, `.some(n)` = last n days.
    private var pendingRecompute: Int?? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?
    private var started = false

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
        if let data = UserDefaults.standard.data(forKey: Self.calibrationKey),
           let c = try? JSONDecoder().decode(Calibration.self, from: data), c.version == Calibration.currentVersion {
            calibration = c
        }
    }

    /// Screen requested by the `-woopScreen <name>` launch argument (CI screenshots).
    let launchScreen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-woopScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    func start() {
        guard !started else { return }
        started = true
        Self.prepareDropFolder()
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
            // Today first, then everything missing or computed by an older version of the engine.
            recompute(daysBack: 3) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.calibration == nil && !self.importedDays.isEmpty {
                        self.refitCalibration()
                    } else {
                        self.recompute(daysBack: nil)
                    }
                }
            }
        }
        if settings.onboardingDone && !settings.demoMode {
            strap.start()
            strap.setBackgroundLive(settings.continuousHR)
            Notifier.shared.requestAuthorization()
        }
        strap.$battery.combineLatest(strap.$charging)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level, charging in
                Task { @MainActor in self?.evaluateBattery(level, charging: charging) }
            }
            .store(in: &cancellables)
        strap.$lastSync
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleTimedNotifications() }
            }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute(daysBack: 1) }
        }
        resumeLiveSessionIfNeeded()
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
        var lo = 0, hi = sortedKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedKeys[mid] <= key { lo = mid + 1 } else { hi = mid }
        }
        return sortedKeys[max(0, lo - count)..<lo].compactMap { days[$0] }
    }

    func loadStored() {
        // Days computed by an older engine stay visible until the recompute pass replaces them.
        let all = Database.shared.allDays()
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
        let merged = Self.merge(computedDays, importedDays)
        // Publishing an identical dictionary would redraw every screen for nothing.
        guard merged != days else { return }
        days = merged
        dataVersion &+= 1
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
        let calibration = settings.demoMode ? nil : self.calibration
        let reach = max(45, min(settings.rawRetentionDays, 120))
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
                // Everything missing or stale, as far back as raw seconds are kept.
                let floor = DayKey.adding(-(reach - 1), to: today)
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
                var events: [StoredEvent] = []
                if let demo {
                    samples = Array(TimeIndex.slice(demo, from: from, to: to))
                } else {
                    samples = Database.shared.samples(from: from, to: to)
                    events = Database.shared.events(from: from, to: to, ids: [EventID.wristOn, EventID.wristOff])
                }
                let floorKey = DayKey.adding(-60, to: key)
                let hist = Self.merge(computed.filter { $0.key < key && $0.key >= floorKey },
                                      imported.filter { $0.key < key && $0.key >= floorKey })
                    .values.sorted { $0.date < $1.date }
                var inputs = DayInputs(date: key, samples: samples, profile: settings.profile,
                                       history: Array(hist), userActivities: activities, now: now,
                                       events: events, calibration: calibration)
                if demo == nil, let e = settings.sleepEdits[key], e.count == 2, e[1] > e[0] {
                    inputs.forcedSleep = (e[0], e[1])
                }
                var m = DayEngine.compute(inputs)
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
                self.evaluateNotifications()
                completion?()
                self.runPendingRecompute()
                self.refitCalibrationIfOverlapChanged()
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
        recompute(daysBack: max(45, min(settings.rawRetentionDays, 120)))
    }

    // MARK: Manual sleep correction

    /// Replace the detected night of `date` by the given times (nil = back to automatic detection).
    func setSleepEdit(date: String, start: Int?, end: Int?) {
        if let start, let end, end > start {
            settings.sleepEdits[date] = [start, end]
        } else {
            settings.sleepEdits[date] = nil
        }
        let back = DayKey.startUnix(today).flatMap { t in DayKey.startUnix(date).map { (t - $0) / 86400 + 2 } } ?? 2
        recompute(daysBack: max(2, min(back, 120)))
    }

    // MARK: WHOOP calibration

    /// Learn the personal mappings from the imported WHOOP days (and the nights measured by
    /// both), then rescore the days computed on the phone with them.
    func refitCalibration() {
        guard !settings.demoMode, !calibrationFitting else { return }
        guard !importedDays.isEmpty else {
            if calibration != nil {
                calibration = nil
                UserDefaults.standard.removeObject(forKey: Self.calibrationKey)
                recompute(daysBack: max(45, min(settings.rawRetentionDays, 120)))
            }
            return
        }
        calibrationFitting = true
        let imported = importedDays.values.sorted { $0.date < $1.date }
        let computed = computedDays
        let profile = settings.profile
        analyticsQueue.async {
            let fitted = Calibration.fit(imported: imported, computed: computed, profile: profile, tz: DayEngine.tzOffset)
            Task { @MainActor in
                self.calibrationFitting = false
                guard fitted != self.calibration else {
                    self.recompute(daysBack: nil)
                    return
                }
                self.calibration = fitted
                if let data = try? JSONEncoder().encode(fitted) { UserDefaults.standard.set(data, forKey: Self.calibrationKey) }
                self.recompute(daysBack: max(45, min(self.settings.rawRetentionDays, 120)))
            }
        }
    }

    /// Nights measured both by WHOOP and by this app feed the HRV / resting-HR alignment: refit
    /// when their number changes.
    private func refitCalibrationIfOverlapChanged() {
        guard !settings.demoMode, !importedDays.isEmpty, !calibrationFitting, !computing else { return }
        let overlap = importedDays.keys.filter { computedDays[$0]?.sleep != nil }.count
        if calibration == nil || overlap != calibration?.overlapNights { refitCalibration() }
    }

    // MARK: Notifications

    private static let notifyLogKey = "woop.notify.log"

    private func loadNotifyLog() -> NotifyLog {
        guard let d = UserDefaults.standard.data(forKey: Self.notifyLogKey),
              let l = try? JSONDecoder().decode(NotifyLog.self, from: d) else { return NotifyLog() }
        return l
    }

    private func saveNotifyLog(_ l: NotifyLog) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: Self.notifyLogKey) }
    }

    /// After each rescoring: activity detected, morning recovery / sleep, Health Monitor,
    /// Strain Coach (see NotificationPlanner), then the scheduled ones.
    func evaluateNotifications() {
        guard settings.onboardingDone, !settings.demoMode else { return }
        let ctx = NotifyContext(days: days, today: today, now: Int(Date().timeIntervalSince1970),
                                dataEnd: Database.shared.newestSampleTs(), firstName: settings.profile.firstName,
                                prefs: settings.notify, bedtime: recommendedBedtime.map { Int($0.timeIntervalSince1970) })
        var log = loadNotifyLog()
        let list = NotificationPlanner.plan(ctx, log: &log)
        saveNotifyLog(log)
        for n in list { Notifier.shared.post(n) }
        scheduleTimedNotifications()
    }

    private func evaluateBattery(_ level: Double?, charging: Bool) {
        guard let level, settings.onboardingDone, !settings.demoMode else { return }
        var log = loadNotifyLog()
        let n = NotificationPlanner.battery(level: level, charging: charging, prefs: settings.notify, log: &log)
        saveNotifyLog(log)
        if let n { Notifier.shared.post(n) }
    }

    /// Bedtime reminder, Monday summary and the "not synced for 10 h" reminder are scheduled
    /// ahead, so they arrive even if iOS keeps Woop asleep.
    func scheduleTimedNotifications() {
        let n = Notifier.shared
        guard settings.onboardingDone, !settings.demoMode else {
            n.cancel(["bedtime", "weekly", "sync-reminder"])
            return
        }
        let p = settings.notify
        let now = Date()
        if p.bedtime, let bed = recommendedBedtime {
            var fire = bed.addingTimeInterval(-Double(p.bedtimeLeadMinutes * 60))
            while fire < now.addingTimeInterval(60) { fire = fire.addingTimeInterval(86400) }
            let need = days[today]?.tonightNeedSec
            n.schedule(NotificationPlanner.bedtime(bedtime: Int(fire.timeIntervalSince1970) + p.bedtimeLeadMinutes * 60, needSec: need), at: fire)
        } else {
            n.cancel(["bedtime"])
        }
        if p.weekly {
            let cal = DayKey.calendar
            let todayStart = cal.startOfDay(for: now)
            let weekday = cal.component(.weekday, from: now) // 2 = Monday
            var monday = cal.date(byAdding: .day, value: (9 - weekday) % 7, to: todayStart) ?? todayStart
            var fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
            if fire <= now {
                monday = cal.date(byAdding: .day, value: 7, to: monday) ?? monday
                fire = cal.date(byAdding: .day, value: 7, to: fire) ?? fire
            }
            let mondayKey = DayKey.key(monday)
            // The week is complete only on the Monday itself (before 9:00).
            let summary = mondayKey == today ? NotificationPlanner.weekly(days: days, monday: mondayKey) : nil
            n.schedule(summary ?? NotificationPlanner.weeklyGeneric(), at: fire)
        } else {
            n.cancel(["weekly"])
        }
        if p.syncReminder, strap.pairedID != nil {
            var fire = (strap.lastSync ?? now).addingTimeInterval(NotificationPlanner.syncReminderDelay)
            if fire < now.addingTimeInterval(60) { fire = now.addingTimeInterval(NotificationPlanner.syncReminderDelay) }
            let h = DayKey.calendar.component(.hour, from: fire)
            if h >= 23 || h < 8 {
                // Not at night: the next morning at 8:15.
                var morning = DayKey.calendar.date(bySettingHour: 8, minute: 15, second: 0, of: fire) ?? fire
                if morning < fire { morning = DayKey.calendar.date(byAdding: .day, value: 1, to: morning) ?? morning }
                fire = morning
            }
            n.schedule(NotificationPlanner.syncReminder(), at: fire)
        } else {
            n.cancel(["sync-reminder"])
        }
    }

    /// "Envoyer une notification de test": the latest activity (or an example), 5 s later.
    func sendTestNotification() {
        let latest = days.values.sorted { $0.date > $1.date }.first { !$0.activities.isEmpty }
        var p: PlannedNotification
        if let d = latest, let a = d.activities.last {
            p = NotificationPlanner.activity(a, day: d.date)
        } else {
            var a = ActivityRecord(id: "test", sport: "course", start: Int(Date().timeIntervalSince1970) - 2700,
                                   end: Int(Date().timeIntervalSince1970) - 300, source: .auto)
            a.strain = 11.4
            a.calories = 612
            a.avgHR = 151
            p = NotificationPlanner.activity(a, day: today)
        }
        p.id = "test-\(Int(Date().timeIntervalSince1970))"
        Notifier.shared.post(p, after: 5)
    }

    /// A tapped notification (or one of its buttons).
    func handleNotification(route: String, action: String) {
        let parts = route.split(separator: ":", maxSplits: 2).map(String.init)
        guard let kind = parts.first else { return }
        let day = parts.count > 1 ? parts[1] : today
        switch kind {
        case "activity":
            let id = parts.count > 2 ? parts[2] : ""
            if action == Notifier.actionConfirm {
                if let d = days[day], let a = ActivityDetailView.find(id, in: d) { confirmActivity(a, sport: a.sport) }
                return
            }
            if action == Notifier.actionChange { pendingSportEdit = id }
            deepLink = .route(day: day, .activity(id))
        case "activities": deepLink = .route(day: day, .activities)
        case "recovery": deepLink = .route(day: day, .recovery)
        case "sleep": deepLink = .route(day: day, .sleep)
        case "strain": deepLink = .route(day: day, .strain)
        case "device": deepLink = .route(day: today, .device)
        case "planner": deepLink = .planner
        case "health": deepLink = .tab(.health)
        case "community": deepLink = .tab(.community)
        default: deepLink = .home
        }
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
        start()
        scheduleBackgroundRefresh()
        // After a relaunch the strap needs a few seconds to reconnect and finish its handshake.
        for _ in 0..<12 where strap.pairedID != nil && strap.state != .connected {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        _ = await strap.syncAndWait(timeout: 16)
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

    /// Confirm an activity with a sport (auto-detected ones become saved activities; others are
    /// retyped in place, including imported WHOOP workouts).
    func confirmActivity(_ a: ActivityRecord, sport: String) {
        var n = a
        n.sport = sport
        if a.source == .auto {
            n.id = "manual-\(a.start)"
            n.source = .manual
        }
        if !settings.demoMode {
            if n.id != a.id { Database.shared.deleteActivity(id: a.id) }
            Database.shared.saveActivity(n)
        }
        userActivities.removeAll { $0.id == a.id || $0.id == n.id }
        userActivities.append(n)
        if a.source == .imported {
            for (k, var d) in importedDays where d.activities.contains(where: { $0.id == a.id }) {
                d.activities = d.activities.map { $0.id == a.id ? n : $0 }
                importedDays[k] = d
                if !settings.demoMode { Database.shared.saveImportedDays([d]) }
            }
            rebuildMerged()
        }
        // Show the new type right away, then rescore.
        for (k, var d) in computedDays where d.activities.contains(where: { $0.id == a.id }) {
            d.activities = d.activities.map { $0.id == a.id ? n : $0 }
            computedDays[k] = d
        }
        rebuildMerged()
        let back = max(2, (DayKey.startUnix(today).map { ($0 - a.start) / 86400 + 2 } ?? 2))
        recompute(daysBack: min(back, 45))
    }

    // MARK: Live activity session

    func startLiveSession(sport: String) {
        let s = LiveSession(sport: sport, start: Int(Date().timeIntervalSince1970))
        liveSession = s
        persistLive()
        strap.setLiveWanted(true)
        LiveWorkout.shared.begin(s, day: days[today], profile: settings.profile, routeTracking: settings.routeTracking)
    }

    func changeLiveSport(_ sport: String) {
        guard var s = liveSession else { return }
        s.sport = sport
        liveSession = s
        persistLive()
    }

    func endLiveSession(save: Bool) {
        guard let s = liveSession else { return }
        liveSession = nil
        persistLive()
        strap.setLiveWanted(false)
        let gps = LiveWorkout.shared.finish()
        let end = Int(Date().timeIntervalSince1970)
        if save, end - s.start >= 60 {
            var a = ActivityRecord(id: "live-\(s.start)", sport: s.sport, start: s.start, end: end, source: .live)
            a.route = gps.route
            a.distanceKm = gps.distanceKm
            addActivity(a)
        }
    }

    /// After a relaunch during an activity: resume the live figures.
    func resumeLiveSessionIfNeeded() {
        guard let s = liveSession else { return }
        strap.setLiveWanted(true)
        LiveWorkout.shared.begin(s, day: days[today], profile: settings.profile, routeTracking: settings.routeTracking)
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
