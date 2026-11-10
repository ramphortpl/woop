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
        /// Files read, with what they contained (nil = not a WHOOP table).
        var files: [(name: String, kind: Kind?)] = []
        var firstDay: String? { days.first?.date }
        var lastDay: String? { days.last?.date }
    }

    struct NamedText {
        var name: String
        var text: String
    }

    enum Kind: String { case cycles, sleeps, workouts, journal }

    // MARK: CSV

    /// RFC-4180-style parser (quotes, escaped quotes, CRLF), BOM-tolerant. The delimiter is
    /// detected from the header line, so a file re-saved by a French spreadsheet (";") works.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        let delimiter = detectDelimiter(it)
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
                case delimiter: row.append(field); field = ""
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

    /// The most frequent of `,` `;` and tab on the first line (outside quotes).
    static func detectDelimiter(_ chars: [Character]) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for c in chars {
            if c == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if c == "\n" || c == "\r\n" || c == "\r" { break }
            if counts[c] != nil { counts[c, default: 0] += 1 }
        }
        let best = counts.max { a, b in a.value < b.value || (a.value == b.value && a.key != ",") }
        return (best?.value ?? 0) > 0 ? best!.key : ","
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
        let out = normalizeRaw(header)
        return aliases[out] ?? out
    }

    /// Header in snake_case ASCII, before the French → English alias map.
    static func normalizeRaw(_ header: String) -> String {
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
        return out
    }

    struct Table {
        let headers: [String]
        let rows: [[String]]
        /// The export's language (English headers), which decides what "Football" means.
        var english = false

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
        let raw = head.map(normalizeRaw)
        var t = Table(headers: raw.map { aliases[$0] ?? $0 }, rows: Array(rows.dropFirst()))
        t.english = raw.contains("activity_name") || raw.contains("cycle_start_time") || raw.contains("workout_start_time")
        return t
    }

    static func kind(of t: Table) -> Kind? {
        let h = Set(t.headers)
        if h.contains("activity_name") || h.contains("workout_start_time") { return .workouts }
        if h.contains("nap") && (h.contains("sleep_onset") || h.contains("wake_onset")) { return .sleeps }
        if h.contains("cycle_start_time") && (h.contains("recovery_score_pct") || h.contains("day_strain")) { return .cycles }
        if h.contains("sleep_onset") || h.contains("asleep_duration_min") { return .sleeps }
        if h.contains("question_text") || h.contains("answered_yes") || h.contains("texte_de_la_question") { return .journal }
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
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "T", with: " ")
        var offset = offsetMinutes
        // An explicit zone on the value itself ("…Z", "…+01:00") wins over the cycle's zone.
        if s.hasSuffix("Z") {
            s.removeLast()
            offset = 0
        } else if s.count > 16, let r = s.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) {
            offset = WhoopExport.offsetMinutes(String(s[r]))
            s = String(s[..<r.lowerBound])
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if let dot = s.firstIndex(of: "."), s.distance(from: s.startIndex, to: dot) >= 16 { s = String(s[..<dot]) }
        formatter.timeZone = TimeZone(secondsFromGMT: offset * 60) ?? TimeZone(identifier: "UTC")
        for p in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
                  "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "yyyy-MM-dd", "dd/MM/yyyy"] {
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
        importFiles(texts.enumerated().map { NamedText(name: "fichier \($0.offset + 1)", text: $0.element) })
    }

    static func importFiles(_ files: [NamedText]) -> Result {
        var result = Result()
        var days: [String: DayMetrics] = [:]
        var naps: [(key: String, s: SleepSession)] = []
        for file in files {
            let t = table(file.text)
            let k = t.flatMap(kind(of:))
            result.files.append((file.name, k))
            guard let t, let k else { continue }
            switch k {
            case .journal:
                continue
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
                    var a = ActivityRecord(id: "whoop-\(s)", sport: SportCatalog.match(whoopName: name, englishExport: t.english),
                                           start: s, end: e, source: .imported)
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
        var sorted = days.values.sorted { $0.date < $1.date }
        // Each workout goes to the cycle that contains it (else the calendar day it started).
        for a in result.activities {
            if let i = sorted.firstIndex(where: { d in
                guard let s = d.cycleStart else { return false }
                return a.start >= s && a.start < (d.cycleEnd ?? s + 30 * 3600)
            }) ?? sorted.firstIndex(where: { $0.date == DayKey.key(unix: a.start) }) {
                sorted[i].activities.append(a)
            }
        }
        result.days = sorted
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
            if let local = d.sleep {
                m.stages = local.stages; m.hrv = local.hrv; m.rhr = local.rhr; m.avgHR = local.avgHR
                m.highStressPct = local.highStressPct; m.hrvWindows = local.hrvWindows; m.hrvNoise = local.hrvNoise
            }
            d.sleep = m
        }
        if let need = d.sleepNeedSec, need > 0, let s = d.sleep {
            d.sleepHoursVsNeed = min(100, Double(s.asleepSec) / need * 100)
        }
        if imp.recovery != nil { d.recoveryCalibrated = nil }
        if !imp.naps.isEmpty { d.naps = imp.naps }
        if d.calibrationNights != nil && d.recovery != nil { d.calibrationNights = nil }
        return d
    }
}

// MARK: - Export files (zip / csv / folders)

extension WhoopExport {
    struct Collected {
        var texts: [NamedText] = []
        /// Files skipped (not CSV, system junk), for the import report.
        var ignored: [String] = []
        var errors: [String] = []
    }

    /// Turn picked files (a .zip, CSVs, files from a folder) into CSV texts. Zips are recognized
    /// by content, whatever their extension; nested zips are opened one level deep.
    static func collect(_ files: [ZipArchive.File], depth: Int = 0) -> Collected {
        var out = Collected()
        for f in files {
            let base = (f.name as NSString).lastPathComponent
            if f.name.contains("__MACOSX/") || base.hasPrefix("._") || base == ".DS_Store" || base.isEmpty { continue }
            if ZipArchive.isZip(f.bytes) {
                guard depth < 2 else { out.ignored.append(base); continue }
                let z = ZipArchive.files(f.bytes)
                out.errors += z.errors
                if z.files.isEmpty && z.errors.isEmpty { out.errors.append("\(base) : archive vide ou illisible") }
                let inner = collect(z.files, depth: depth + 1)
                out.texts += inner.texts
                out.ignored += inner.ignored
                out.errors += inner.errors
                continue
            }
            let ext = (base as NSString).pathExtension.lowercased()
            guard ["csv", "txt", "tsv", ""].contains(ext) || ext.count > 4 else { out.ignored.append(base); continue }
            guard let text = decodeText(f.bytes), looksLikeTable(text) else { out.ignored.append(base); continue }
            out.texts.append(NamedText(name: base, text: text))
        }
        return out
    }

    /// UTF-8 (with or without BOM), UTF-16 with BOM, else Windows-1252 / Latin-1.
    static func decodeText(_ b: [UInt8]) -> String? {
        if b.count >= 2 && b[0] == 0xFF && b[1] == 0xFE { return String(bytes: b.dropFirst(2), encoding: .utf16LittleEndian) }
        if b.count >= 2 && b[0] == 0xFE && b[1] == 0xFF { return String(bytes: b.dropFirst(2), encoding: .utf16BigEndian) }
        if let s = String(bytes: b, encoding: .utf8) { return s }
        return String(bytes: b, encoding: .windowsCP1252) ?? String(bytes: b, encoding: .isoLatin1)
    }

    /// A header line with several delimited columns (cheap check before parsing).
    static func looksLikeTable(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: \.isNewline).first else { return false }
        let n = first.filter { $0 == "," || $0 == ";" || $0 == "\t" }.count
        return n >= 2
    }
}
