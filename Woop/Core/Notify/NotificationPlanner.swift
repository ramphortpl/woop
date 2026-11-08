import Foundation

/// Which notifications the user wants (Plus › Notifications). All on by default.
struct NotifyPrefs: Codable, Equatable, Sendable {
    var activities = true
    var recovery = true
    var sleep = true
    var strainCoach = true
    var bedtime = true
    var bedtimeLeadMinutes = 30
    var healthMonitor = true
    var battery = true
    var syncReminder = true
    var weekly = true
}

extension NotifyPrefs {
    /// Missing keys keep their default (settings written by an older version stay valid).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotifyPrefs()
        activities = (try? c.decodeIfPresent(Bool.self, forKey: .activities)) ?? d.activities
        recovery = (try? c.decodeIfPresent(Bool.self, forKey: .recovery)) ?? d.recovery
        sleep = (try? c.decodeIfPresent(Bool.self, forKey: .sleep)) ?? d.sleep
        strainCoach = (try? c.decodeIfPresent(Bool.self, forKey: .strainCoach)) ?? d.strainCoach
        bedtime = (try? c.decodeIfPresent(Bool.self, forKey: .bedtime)) ?? d.bedtime
        bedtimeLeadMinutes = (try? c.decodeIfPresent(Int.self, forKey: .bedtimeLeadMinutes)) ?? d.bedtimeLeadMinutes
        healthMonitor = (try? c.decodeIfPresent(Bool.self, forKey: .healthMonitor)) ?? d.healthMonitor
        battery = (try? c.decodeIfPresent(Bool.self, forKey: .battery)) ?? d.battery
        syncReminder = (try? c.decodeIfPresent(Bool.self, forKey: .syncReminder)) ?? d.syncReminder
        weekly = (try? c.decodeIfPresent(Bool.self, forKey: .weekly)) ?? d.weekly
    }
}

/// What was already notified, so nothing is ever sent twice.
struct NotifyLog: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        var start: Int
        var end: Int
    }

    var initialized = false
    var activities: [Window] = []
    var recoveryDay: String?
    var sleepDay: String?
    var healthDay: String?
    var strainTargetDay: String?
    var strainOverDay: String?
    var batteryLowArmed = true
    var batteryCriticalArmed = true
    var batteryFullArmed = true
}

extension NotifyLog {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialized = (try? c.decodeIfPresent(Bool.self, forKey: .initialized)) ?? false
        activities = (try? c.decodeIfPresent([Window].self, forKey: .activities)) ?? []
        recoveryDay = try? c.decodeIfPresent(String.self, forKey: .recoveryDay)
        sleepDay = try? c.decodeIfPresent(String.self, forKey: .sleepDay)
        healthDay = try? c.decodeIfPresent(String.self, forKey: .healthDay)
        strainTargetDay = try? c.decodeIfPresent(String.self, forKey: .strainTargetDay)
        strainOverDay = try? c.decodeIfPresent(String.self, forKey: .strainOverDay)
        batteryLowArmed = (try? c.decodeIfPresent(Bool.self, forKey: .batteryLowArmed)) ?? true
        batteryCriticalArmed = (try? c.decodeIfPresent(Bool.self, forKey: .batteryCriticalArmed)) ?? true
        batteryFullArmed = (try? c.decodeIfPresent(Bool.self, forKey: .batteryFullArmed)) ?? true
    }
}

/// A notification to show. `route` is opened when it is tapped ("activity:<jour>:<id>", …).
struct PlannedNotification: Equatable, Sendable {
    enum Kind: String, Sendable {
        case activity, recovery, sleep, health, strainTarget, strainOver, battery, bedtime, weekly, syncReminder, test
    }

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var route: String
    var thread: String
    /// Offer "Confirmer" / "Changer de sport" (auto-detected activities).
    var activityActions = false
}

struct NotifyContext: Sendable {
    var days: [String: DayMetrics]
    var today: String
    var now: Int
    /// Newest stored strap sample (unix s): tells whether an activity or a night is over.
    var dataEnd: Int?
    var firstName: String = ""
    var prefs = NotifyPrefs()
    /// Recommended bedtime tonight (unix s), mentioned after a very hard day.
    var bedtime: Int?
}

/// Decides which WHOOP-style notifications to send after each rescoring: an activity detected
/// (once it is over), the morning recovery and sleep, the Health Monitor, the Strain Coach target
/// reached or exceeded. Pure logic, so it is tested on any platform.
enum NotificationPlanner {
    /// An auto-detected activity is notified once this much calm data follows it.
    static let activitySettle = 10 * 60
    /// The night is over once this much awake data follows the last sleep minute.
    static let wakeSettle = 20 * 60

    static func plan(_ c: NotifyContext, log: inout NotifyLog) -> [PlannedNotification] {
        let yesterday = DayKey.adding(-1, to: c.today)
        log.activities.removeAll { $0.end < c.now - 4 * 86400 }
        let dataEnd = c.dataEnd ?? 0
        let candidates: [(day: String, a: ActivityRecord)] = [yesterday, c.today].flatMap { k in
            (c.days[k]?.activities ?? []).map { (k, $0) }
        }
        let todayDay = c.days[c.today]

        // First evaluation after install/update: remember the current state, send nothing.
        guard log.initialized else {
            for x in candidates { log.activities.append(.init(start: x.a.start, end: x.a.end)) }
            if let d = todayDay {
                if d.recovery != nil { log.recoveryDay = c.today }
                if d.sleep != nil { log.sleepDay = c.today; log.healthDay = c.today }
                if let r = d.recovery, let st = d.strain, let t = StrainTarget.forRecovery(r) {
                    if st >= t.lowerBound { log.strainTargetDay = c.today }
                    if st > t.upperBound + 1 { log.strainOverDay = c.today }
                }
            }
            log.initialized = true
            return []
        }

        var out: [PlannedNotification] = []

        // Activities: auto-detected ones once they are over, live ones once scored.
        var fresh: [(day: String, a: ActivityRecord)] = []
        for x in candidates {
            let a = x.a
            guard a.source == .auto || a.source == .live, a.strain != nil else { continue }
            guard c.now - a.end <= (a.source == .auto ? 8 : 12) * 3600 else { continue }
            if a.source == .auto && dataEnd < a.end + activitySettle { continue }
            if log.activities.contains(where: { $0.start < a.end && a.start < $0.end }) { continue }
            fresh.append(x)
        }
        for x in fresh { log.activities.append(.init(start: x.a.start, end: x.a.end)) }
        if c.prefs.activities {
            if fresh.count > 2 {
                let lines = fresh.map { "\(SportCatalog.displayName($0.a)) \(Fmt.clock($0.a.start))–\(Fmt.clock($0.a.end)) (effort \(Fmt.dec1($0.a.strain)))" }
                out.append(PlannedNotification(id: "activities-\(c.today)-\(fresh.count)", kind: .activity,
                                               title: "\(fresh.count) activités détectées",
                                               body: lines.joined(separator: " · ") + ". Touche pour les voir.",
                                               route: "activities:\(fresh.last!.day)", thread: "activities"))
            } else {
                out += fresh.map { activity($0.a, day: $0.day) }
            }
        }

        // Morning: recovery (or sleep while calibrating) and Health Monitor, once the night is over.
        if let d = todayDay, let s = d.sleep, c.now - s.end < 8 * 3600, dataEnd >= s.end + wakeSettle {
            if c.prefs.recovery, log.recoveryDay != c.today, let r = d.recovery {
                out.append(recovery(d, r, s, firstName: c.firstName))
                log.recoveryDay = c.today
                log.sleepDay = c.today
            }
            if c.prefs.sleep, log.sleepDay != c.today, let perf = d.sleepPerformance {
                out.append(sleep(d, s, perf))
                log.sleepDay = c.today
            }
            if log.healthDay != c.today {
                log.healthDay = c.today
                let hist = c.days.values.filter { $0.date < c.today }.sorted { $0.date < $1.date }.suffix(30)
                let flags = HealthMonitor.deviations(d, history: Array(hist))
                if c.prefs.healthMonitor, flags.count >= 2 {
                    out.append(PlannedNotification(
                        id: "health-\(c.today)", kind: .health,
                        title: "Moniteur de santé : \(flags.count) indicateurs inhabituels",
                        body: flags.map(\.text).joined(separator: ", ") + ". Écoute ton corps aujourd'hui : repos et hydratation.",
                        route: "health", thread: "health"))
                }
            }
        }

        // Strain Coach: target reached / clearly exceeded (daytime only).
        let minute = DayKey.minuteOfDay(unix: c.now)
        if c.prefs.strainCoach, minute >= 7 * 60, minute <= 22 * 60 + 30,
           let d = todayDay, let r = d.recovery, let st = d.strain, let t = StrainTarget.forRecovery(r) {
            if st > t.upperBound + 1, log.strainOverDay != c.today {
                log.strainOverDay = c.today
                log.strainTargetDay = c.today
                var body = "Effort \(Fmt.dec1(st)), au-dessus de ta cible (\(Fmt.dec1(t.lowerBound))–\(Fmt.dec1(t.upperBound))) pour une récupération de \(Int(r.rounded())) %."
                body += c.bedtime.map { " Récupère bien ce soir : coucher conseillé vers \(Fmt.clock($0))." } ?? " Pense à bien récupérer ce soir."
                out.append(PlannedNotification(id: "strain-over-\(c.today)", kind: .strainOver,
                                               title: "Au-delà de ton effort optimal", body: body,
                                               route: "strain:\(c.today)", thread: "strain"))
            } else if st >= t.lowerBound, log.strainTargetDay != c.today {
                log.strainTargetDay = c.today
                out.append(PlannedNotification(
                    id: "strain-target-\(c.today)", kind: .strainTarget, title: "Effort optimal atteint 🎯",
                    body: "Effort \(Fmt.dec1(st)) : tu es dans ta zone cible (\(Fmt.dec1(t.lowerBound))–\(Fmt.dec1(t.upperBound))) pour une récupération de \(Int(r.rounded())) %.",
                    route: "strain:\(c.today)", thread: "strain"))
            }
        }
        return out
    }

    // MARK: Contents

    static func activity(_ a: ActivityRecord, day: String) -> PlannedNotification {
        let name = SportCatalog.displayName(a)
        var facts = ["\(Fmt.clock(a.start))–\(Fmt.clock(a.end))", Fmt.duration(a.durationSec), "Effort \(Fmt.dec1(a.strain))"]
        if let k = a.calories { facts.append("\(Fmt.int(k)) kcal") }
        if let h = a.avgHR { facts.append("FC moy. \(Int(h.rounded()))") }
        let body: String
        let title: String
        if a.source == .live {
            title = "Activité enregistrée : \(name)"
            body = facts.joined(separator: " · ") + "."
        } else if a.sport == SportCatalog.generic {
            title = "Activité détectée"
            body = facts.joined(separator: " · ") + ". Quel sport était-ce ? Touche pour le choisir."
        } else {
            title = "Activité détectée : \(name)"
            body = facts.joined(separator: " · ") + ". Touche pour confirmer ou changer le sport."
        }
        return PlannedNotification(id: "activity-\(a.start)", kind: .activity, title: title, body: body,
                                   route: "activity:\(day):\(a.id)", thread: "activities", activityActions: a.source == .auto)
    }

    static func recovery(_ d: DayMetrics, _ r: Double, _ s: SleepSession, firstName: String) -> PlannedNotification {
        let zone = Recovery.zone(r)
        let emoji = zone == .green ? "🟢" : (zone == .yellow ? "🟡" : "🔴")
        let advice: String
        switch zone {
        case .green: advice = "Ton corps est prêt pour un effort important."
        case .yellow: advice = "Récupération moyenne : un effort modéré est adapté."
        case .red: advice = "Ton corps a besoin de récupérer aujourd'hui."
        }
        var body = firstName.isEmpty ? "" : "Bonjour \(firstName) ! "
        body += advice
        body += " Sommeil \(Fmt.hm(Double(s.asleepSec)))"
        if let p = d.sleepPerformance { body += " (\(Int(p.rounded())) % de ton besoin)" }
        body += "."
        if let t = StrainTarget.forRecovery(r) { body += " Effort conseillé : \(Fmt.dec1(t.lowerBound))–\(Fmt.dec1(t.upperBound))." }
        return PlannedNotification(id: "recovery-\(d.date)", kind: .recovery, title: "\(emoji) Récupération : \(Int(r.rounded())) %",
                                   body: body, route: "recovery:\(d.date)", thread: "morning")
    }

    static func sleep(_ d: DayMetrics, _ s: SleepSession, _ perf: Double) -> PlannedNotification {
        var body = "\(Fmt.hm(Double(s.asleepSec))) de sommeil"
        if let need = d.sleepNeedSec { body += " pour un besoin de \(Fmt.hm(need))" }
        body += "."
        if d.recovery == nil, let n = d.calibrationNights {
            body += " Calibrage de ta récupération : \(n)/\(Recovery.calibrationNights) nuits."
        }
        return PlannedNotification(id: "sleep-\(d.date)", kind: .sleep, title: "Sommeil analysé : \(Int(perf.rounded())) %",
                                   body: body, route: "sleep:\(d.date)", thread: "morning")
    }

    /// Battery notifications (low, very low, full), each re-armed by the next charge cycle.
    static func battery(level: Double, charging: Bool, prefs: NotifyPrefs, log: inout NotifyLog) -> PlannedNotification? {
        if charging || level >= 40 {
            log.batteryLowArmed = true
            log.batteryCriticalArmed = true
        }
        if !charging && level < 90 { log.batteryFullArmed = true }
        let pct = Int(level.rounded())
        if charging && level >= 99.5 && log.batteryFullArmed {
            log.batteryFullArmed = false
            guard prefs.battery else { return nil }
            return PlannedNotification(id: "battery-full", kind: .battery, title: "Bracelet rechargé",
                                       body: "Ton WHOOP est chargé à 100 %.", route: "device", thread: "battery")
        }
        if !charging && level <= 10 && log.batteryCriticalArmed {
            log.batteryCriticalArmed = false
            log.batteryLowArmed = false
            guard prefs.battery else { return nil }
            return PlannedNotification(id: "battery-low", kind: .battery, title: "Batterie du bracelet très faible : \(pct) %",
                                       body: "Recharge ton WHOOP maintenant pour ne pas interrompre l'enregistrement de tes données.",
                                       route: "device", thread: "battery")
        }
        if !charging && level <= 20 && log.batteryLowArmed {
            log.batteryLowArmed = false
            guard prefs.battery else { return nil }
            return PlannedNotification(id: "battery-low", kind: .battery, title: "Batterie du bracelet faible : \(pct) %",
                                       body: "Pense à recharger ton WHOOP aujourd'hui.", route: "device", thread: "battery")
        }
        return nil
    }

    static func bedtime(bedtime: Int, needSec: Double?) -> PlannedNotification {
        var body = "Couche-toi vers \(Fmt.clock(bedtime))"
        if let n = needSec { body += " pour dormir \(Fmt.duration(Int(n))) et répondre à ton besoin de sommeil." } else { body += "." }
        return PlannedNotification(id: "bedtime", kind: .bedtime, title: "Bientôt l'heure de dormir 🌙", body: body,
                                   route: "planner", thread: "sleep-planner")
    }

    static let syncReminderDelay: TimeInterval = 10 * 3600

    static func syncReminder() -> PlannedNotification {
        PlannedNotification(id: "sync-reminder", kind: .syncReminder, title: "Bracelet non synchronisé",
                            body: "Woop n'a pas reçu de données de ton WHOOP depuis 10 h. Ouvre l'app, bracelet à proximité, pour mettre à jour tes scores.",
                            route: "device", thread: "sync")
    }

    /// Summary of the Monday–Sunday week before `monday` (nil without data).
    static func weekly(days: [String: DayMetrics], monday: String) -> PlannedNotification? {
        let week = (1...7).compactMap { days[DayKey.adding(-$0, to: monday)] }
        let rec = week.compactMap(\.recovery)
        let sleeps = week.compactMap(\.sleep)
        let perf = week.compactMap(\.sleepPerformance)
        let strain = week.compactMap(\.strain)
        let acts = week.flatMap(\.activities)
        guard !rec.isEmpty || !sleeps.isEmpty || !strain.isEmpty else { return nil }
        var parts: [String] = []
        if let m = Stats.mean(rec) { parts.append("Récupération moy. \(Int(m.rounded())) %") }
        if let m = Stats.mean(sleeps.map { Double($0.asleepSec) }) {
            var t = "Sommeil moy. \(Fmt.hm(m))"
            if let p = Stats.mean(perf) { t += " (\(Int(p.rounded())) %)" }
            parts.append(t)
        }
        if let m = Stats.mean(strain) { parts.append("Effort moy. \(Fmt.dec1(m))") }
        if !acts.isEmpty {
            let total = acts.reduce(0) { $0 + $1.durationSec }
            parts.append("\(acts.count) activité\(acts.count > 1 ? "s" : "") (\(Fmt.duration(total)))")
        }
        return PlannedNotification(id: "weekly", kind: .weekly, title: "Ton bilan de la semaine",
                                   body: parts.joined(separator: " · ") + ".", route: "community", thread: "weekly")
    }

    static func weeklyGeneric() -> PlannedNotification {
        PlannedNotification(id: "weekly", kind: .weekly, title: "Ton bilan de la semaine",
                            body: "Récupération, sommeil et effort de tes 7 derniers jours : touche pour les voir.",
                            route: "community", thread: "weekly")
    }
}

/// Overnight vitals outside the wearer's own range (same bands as the Santé screen).
enum HealthMonitor {
    struct Flag: Equatable {
        var metric: String
        var text: String
    }

    static func range(_ v: [Double], floor: Double) -> ClosedRange<Double>? {
        guard v.count >= 4, let m = Stats.mean(v), let sd = Stats.std(v) else { return nil }
        let w = max(1.5 * sd, floor)
        return (m - w)...(m + w)
    }

    static func deviations(_ d: DayMetrics, history: [DayMetrics]) -> [Flag] {
        var out: [Flag] = []
        func check(_ id: String, _ name: String, _ value: Double?, _ hist: [Double], floor: Double, unit: String, decimals: Bool) {
            guard let v = value, let r = range(hist, floor: floor), !r.contains(v) else { return }
            let f: (Double) -> String = { decimals ? Fmt.dec1($0) : "\(Int($0.rounded()))" }
            let dir = v > r.upperBound ? "élevée" : "basse"
            out.append(Flag(metric: id, text: "\(name) \(dir) (\(f(v))\(unit), norme \(f(r.lowerBound))–\(f(r.upperBound)))"))
        }
        check("rhr", "FC au repos", d.rhr, history.compactMap(\.rhr), floor: 2, unit: " bpm", decimals: false)
        check("hrv", "VFC", d.hrv, history.compactMap(\.hrv), floor: 4, unit: " ms", decimals: false)
        check("resp", "Fréquence respiratoire", d.respRate, history.compactMap(\.respRate), floor: 0.6, unit: " rpm", decimals: true)
        check("spo2", "Oxygène sanguin", d.spo2, history.compactMap(\.spo2), floor: 1, unit: " %", decimals: true)
        check("temp", "Température cutanée", d.skinTemp, history.compactMap(\.skinTemp), floor: 0.4, unit: " °C", decimals: true)
        return out
    }
}
