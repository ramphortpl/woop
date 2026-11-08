import Foundation

/// Importer for the official WHOOP data export (physiological_cycles.csv, sleeps/sommeil.csv,
/// workouts/entrainements.csv), in English or French. Imported days carry WHOOP's own scores, so
/// past days show exactly what WHOOP computed and the personal baselines start calibrated.
///
/// Column names and the French export's localized headers/filenames are facts about WHOOP's
/// export format (documented by NOOP from real exports, issues #3/#79).
enum WhoopExport {
    struct Result {
        var days: [DayMetrics] = []
        var activities: [ActivityRecord] = []
        var cycles = 0
        var sleeps = 0
        var workouts = 0
    }

    enum Kind { case cycles, sleeps, workouts }

    // MARK: CSV

    /// RFC-4180-style parser (quotes, escaped quotes, CRLF), BOM-tolerant.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        it.append("\n")
        var i = 0
        while i < it.count {
            let c = it[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n", "\r\n":
                    row.append(field)
                    field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        return rows
    }

    static let aliases: [String: String] = [
        // French export
        "heure_de_debut_du_cycle": "cycle_start_time",
        "heure_de_fin_du_cycle": "cycle_end_time",
        "fuseau_horaire_du_cycle": "cycle_timezone",
        "score_de_recuperation_pct": "recovery_score_pct",
        "frequence_cardiaque_au_repos_bpm": "resting_heart_rate_bpm",
        "variabilite_de_la_frequence_cardiaque_ms": "heart_rate_variability_ms",
        "temperature_cutanee_celsius": "skin_temp_celsius",
        "niveau_d_oxygene_pct": "blood_oxygen_pct",
        "effort_du_jour": "day_strain",
        "depense_energetique_cal": "energy_burned_cal",
        "fc_max_bpm": "max_hr_bpm",
        "fc_moyenne_bpm": "average_hr_bpm",
        "premiers_signes_de_sommeil": "sleep_onset",
        "premiers_signes_de_reveil": "wake_onset",
        "performance_sommeil_pct": "sleep_performance_pct",
        "frequence_respiratoire_tr_min": "respiratory_rate_rpm",
        "duree_du_sommeil_min": "asleep_duration_min",
        "temps_passe_au_lit_min": "in_bed_duration_min",
        "duree_du_sommeil_leger_min": "light_sleep_duration_min",
        "duree_du_sommeil_profond_min": "deep_sws_duration_min",
        "duree_du_sommeil_paradoxal_min": "rem_duration_min",
        "temps_d_eveil_min": "awake_duration_min",
        "besoins_en_sommeil_min": "sleep_need_min",
        "dette_de_sommeil_min": "sleep_debt_min",
        "efficacite_du_sommeil_pct": "sleep_efficiency_pct",
        "regularite_du_sommeil_pct": "sleep_consistency_pct",
        "sieste": "nap",
        "heure_de_debut_de_l_entrainement": "workout_start_time",
        "heure_de_fin_de_l_entrainement": "workout_end_time",
        "nom_de_l_activite": "activity_name",
        "effort_activite": "activity_strain",
        "zone_fc_1_pct": "hr_zone_1_pct",
        "zone_fc_2_pct": "hr_zone_2_pct",
        "zone_fc_3_pct": "hr_zone_3_pct",
        "zone_fc_4_pct": "hr_zone_4_pct",
        "zone_fc_5_pct": "hr_zone_5_pct",
        // English variants
        "deep_sleep_duration_min": "deep_sws_duration_min",
        "average_heart_rate_bpm": "average_hr_bpm",
        "max_heart_rate_bpm": "max_hr_bpm",
        "respiratory_rate": "respiratory_rate_rpm",
        "heart_rate_variability_rmssd_ms": "heart_rate_variability_ms",
        "blood_oxygen_pct_pct": "blood_oxygen_pct",
    ]

    static func normalize(_ header: String) -> String {
        var s = header.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "%", with: "pct")
        var out = ""
        var lastUnderscore = false
        for ch in s {
            if (ch.isLetter || ch.isNumber) && ch.isASCII {
                out.append(ch)
                lastUnderscore = false
            } else if !lastUnderscore {
                out.append("_")
                lastUnderscore = true
            }
        }
        while out.hasPrefix("_") { out.removeFirst() }
        while out.hasSuffix("_") { out.removeLast() }
        return aliases[out] ?? out
    }

    struct Table {
        let headers: [String]
        let rows: [[String]]

        func cell(_ row: [String], _ keys: String...) -> String? {
            for k in keys {
                if let i = headers.firstIndex(of: k), i < row.count {
                    let v = row[i].trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        func double(_ row: [String], _ keys: String...) -> Double? {
            for k in keys {
                if let i = headers.firstIndex(of: k), i < row.count {
                    let v = row[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                    if let d = Double(v) { return d }
                }
            }
            return nil
        }
    }

    static func table(_ text: String) -> Table? {
        let rows = parseCSV(text)
        guard let head = rows.first else { return nil }
        return Table(headers: head.map(normalize), rows: Array(rows.dropFirst()))
    }

    static func kind(of t: Table) -> Kind? {
        let h = Set(t.headers)
        if h.contains("activity_name") || h.contains("workout_start_time") { return .workouts }
        if h.contains("nap") && (h.contains("sleep_onset") || h.contains("wake_onset")) { return .sleeps }
        if h.contains("cycle_start_time") && (h.contains("recovery_score_pct") || h.contains("day_strain")) { return .cycles }
        if h.contains("sleep_onset") || h.contains("asleep_duration_min") { return .sleeps }
        return nil
    }

    // MARK: Time

    static func offsetMinutes(_ raw: String?) -> Int {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).uppercased(), !s.isEmpty else { return 0 }
        if s.hasPrefix("UTC") || s.hasPrefix("GMT") { s = String(s.dropFirst(3)) }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "Z" { return 0 }
        var sign = 1
        if s.hasPrefix("+") { s.removeFirst() } else if s.hasPrefix("-") { sign = -1; s.removeFirst() }
        let parts = s.split(separator: ":")
        if parts.count == 2 { return sign * ((Int(parts[0]) ?? 0) * 60 + (Int(parts[1]) ?? 0)) }
        let digits = s.prefix { $0.isNumber }
        if digits.count >= 3 { return sign * ((Int(digits.dropLast(2)) ?? 0) * 60 + (Int(digits.suffix(2)) ?? 0)) }
        return sign * (Int(digits) ?? 0) * 60
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    static func parseTime(_ raw: String?, offsetMinutes: Int) -> Int? {
        guard let s0 = raw?.trimmingCharacters(in: .whitespaces), !s0.isEmpty else { return nil }
        let s = s0.replacingOccurrences(of: "T", with: " ")
        formatter.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone(identifier: "UTC")
        for p in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = p
            if let d = formatter.date(from: s) { return Int(d.timeIntervalSince1970) }
        }
        return nil
    }

    /// The wake day of a cycle, in the cycle's own UTC offset.
    static func wakeDayKey(_ unix: Int, offsetMinutes: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(unix)))
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    // MARK: Import

    static func importTexts(_ texts: [String]) -> Result {
        var result = Result()
        var days: [String: DayMetrics] = [:]
        var naps: [(key: String, s: SleepSession)] = []
        for text in texts {
            guard let t = table(text), let k = kind(of: t) else { continue }
            switch k {
            case .cycles:
                for row in t.rows {
                    let tz = offsetMinutes(t.cell(row, "cycle_timezone"))
                    let start = parseTime(t.cell(row, "cycle_start_time"), offsetMinutes: tz)
                    let end = parseTime(t.cell(row, "cycle_end_time"), offsetMinutes: tz)
                    let onset = parseTime(t.cell(row, "sleep_onset"), offsetMinutes: tz)
                    let wake = parseTime(t.cell(row, "wake_onset"), offsetMinutes: tz)
                    guard let anchor = wake ?? end ?? start else { continue }
                    let key = wakeDayKey(anchor, offsetMinutes: tz)
                    var d = days[key] ?? DayMetrics(date: key)
                    d.imported = true
                    d.cycleStart = start
                    d.cycleEnd = end
                    d.recovery = t.double(row, "recovery_score_pct")
                    d.rhr = t.double(row, "resting_heart_rate_bpm")
                    d.hrv = t.double(row, "heart_rate_variability_ms")
                    d.skinTemp = t.double(row, "skin_temp_celsius")
                    d.spo2 = t.double(row, "blood_oxygen_pct")
                    d.strain = t.double(row, "day_strain")
                    d.calories = t.double(row, "energy_burned_cal")
                    d.maxHR = t.double(row, "max_hr_bpm").map { Int($0.rounded()) }
                    d.avgHR = t.double(row, "average_hr_bpm")
                    d.respRate = t.double(row, "respiratory_rate_rpm")
                    d.sleepPerformance = t.double(row, "sleep_performance_pct")
                    d.sleepConsistency = t.double(row, "sleep_consistency_pct")
                    d.sleepNeedSec = t.double(row, "sleep_need_min").map { $0 * 60 }
                    d.sleepDebtSec = t.double(row, "sleep_debt_min").map { $0 * 60 }
                    if let on = onset, let w = wake, w > on {
                        d.sleep = sleepSession(t, row, start: on, end: w, nap: false)
                    }
                    if d.wornMinutes == 0 { d.wornMinutes = 1 }
                    days[key] = d
                    result.cycles += 1
                }
            case .sleeps:
                for row in t.rows {
                    let tz = offsetMinutes(t.cell(row, "cycle_timezone"))
                    guard let on = parseTime(t.cell(row, "sleep_onset"), offsetMinutes: tz),
                          let w = parseTime(t.cell(row, "wake_onset"), offsetMinutes: tz), w > on else { continue }
                    let nap = (t.cell(row, "nap") ?? "").lowercased()
                    let isNap = ["true", "vrai", "1", "yes", "oui"].contains(nap)
                    result.sleeps += 1
                    if isNap { naps.append((wakeDayKey(w, offsetMinutes: tz), sleepSession(t, row, start: on, end: w, nap: true))) }
                }
            case .workouts:
                for row in t.rows {
                    let tz = offsetMinutes(t.cell(row, "cycle_timezone"))
                    guard let s = parseTime(t.cell(row, "workout_start_time"), offsetMinutes: tz),
                          let e = parseTime(t.cell(row, "workout_end_time"), offsetMinutes: tz), e > s else { continue }
                    let name = t.cell(row, "activity_name") ?? "Activité"
                    var a = ActivityRecord(id: "whoop-\(s)", sport: sportKey(name), start: s, end: e, source: .imported)
                    a.strain = t.double(row, "activity_strain")
                    a.calories = t.double(row, "energy_burned_cal")
                    a.avgHR = t.double(row, "average_hr_bpm")
                    a.maxHR = t.double(row, "max_hr_bpm").map { Int($0.rounded()) }
                    var zones = Array(repeating: 0, count: 6)
                    let dur = Double(e - s)
                    for z in 1...5 {
                        if let p = t.double(row, "hr_zone_\(z)_pct") { zones[z] = Int((p / 100 * dur).rounded()) }
                    }
                    a.zoneSeconds = zones
                    a.note = name
                    result.activities.append(a)
                    result.workouts += 1
                }
            }
        }
        for n in naps {
            if var d = days[n.key] { d.naps.append(n.s); days[n.key] = d }
        }
        result.days = days.values.sorted { $0.date < $1.date }
        return result
    }

    static func sleepSession(_ t: Table, _ row: [String], start: Int, end: Int, nap: Bool) -> SleepSession {
        var s = SleepSession(start: start, end: end, isNap: nap)
        func sec(_ k: String) -> Int { Int(((t.double(row, k) ?? 0) * 60).rounded()) }
        s.lightSec = sec("light_sleep_duration_min")
        s.deepSec = sec("deep_sws_duration_min")
        s.remSec = sec("rem_duration_min")
        s.awakeSec = sec("awake_duration_min")
        if s.asleepSec == 0, let asleep = t.double(row, "asleep_duration_min") { s.lightSec = Int(asleep * 60) }
        s.respRate = t.double(row, "respiratory_rate_rpm")
        s.bandDetected = true
        return s
    }

    /// Map a WHOOP activity name (EN/FR) to one of our sport keys.
    static func sportKey(_ name: String) -> String {
        let n = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let table: [(String, String)] = [
            ("run", "course"), ("course", "course"), ("cycl", "cyclisme"), ("velo", "cyclisme"), ("bike", "cyclisme"),
            ("spin", "cyclisme"), ("hik", "randonnee"), ("randon", "randonnee"), ("ruck", "randonnee"),
            ("walk", "marche"), ("marche", "marche"), ("weight", "musculation"), ("muscu", "musculation"),
            ("strength", "musculation"), ("powerlift", "musculation"), ("swim", "natation"), ("natation", "natation"),
            ("yoga", "yoga"), ("hiit", "hiit"), ("functional", "crossfit"), ("crossfit", "crossfit"),
            ("soccer", "football"), ("football", "football"), ("tennis", "tennis"), ("padel", "padel"),
            ("ski", "ski"), ("row", "aviron"), ("aviron", "aviron"), ("box", "boxe"), ("danc", "danse"), ("danse", "danse"),
            ("climb", "escalade"), ("escalade", "escalade"),
        ]
        for (k, v) in table where n.contains(k) { return v }
        return "activite"
    }
}

extension DayMetrics {
    /// Merge WHOOP-imported scores over locally computed ones: WHOOP's own numbers win where
    /// present; the local computation fills everything else (traces, zones, steps, hypnogram).
    static func merged(computed: DayMetrics?, imported: DayMetrics?) -> DayMetrics? {
        guard let imp = imported else { return computed }
        guard var d = computed else { return imp }
        d.imported = true
        d.recovery = imp.recovery ?? d.recovery
        d.hrv = imp.hrv ?? d.hrv
        d.rhr = imp.rhr ?? d.rhr
        d.respRate = imp.respRate ?? d.respRate
        d.spo2 = imp.spo2 ?? d.spo2
        d.skinTemp = imp.skinTemp ?? d.skinTemp
        d.strain = imp.strain ?? d.strain
        d.calories = imp.calories ?? d.calories
        d.avgHR = imp.avgHR ?? d.avgHR
        d.maxHR = imp.maxHR ?? d.maxHR
        d.sleepPerformance = imp.sleepPerformance ?? d.sleepPerformance
        d.sleepConsistency = imp.sleepConsistency ?? d.sleepConsistency
        d.sleepNeedSec = imp.sleepNeedSec ?? d.sleepNeedSec
        d.sleepDebtSec = imp.sleepDebtSec ?? d.sleepDebtSec
        if let s = imp.sleep {
            var m = s
            if let local = d.sleep { m.stages = local.stages; m.hrv = local.hrv; m.rhr = local.rhr; m.avgHR = local.avgHR }
            d.sleep = m
        }
        if !imp.naps.isEmpty { d.naps = imp.naps }
        if d.calibrationNights != nil && d.recovery != nil { d.calibrationNights = nil }
        return d
    }
}
