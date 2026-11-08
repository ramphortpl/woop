import Foundation

/// French display formats (numbers with a decimal comma, "5:40" durations, 24 h clock).
enum Fmt {
    private static let fr = Locale(identifier: "fr_FR")

    static func dec1(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func int(_ v: Double?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.locale = fr
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }

    static func pct(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    /// "5:40" — hours:minutes.
    static func hm(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite else { return "—" }
        let m = Int((s / 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// "38 min" or "2 h 26".
    static func duration(_ seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h " + String(format: "%02d", m % 60)
    }

    /// "5 h 40 min".
    static func hmLong(_ seconds: Double?) -> String {
        guard let s = seconds else { return "—" }
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h " + String(format: "%02d", m % 60)
    }

    static func clock(_ unix: Int?) -> String {
        guard let unix else { return "—" }
        return clock(Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "H:mm"
        return f.string(from: d)
    }

    static func clock24(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func minuteOfDay(_ m: Int) -> String {
        String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }

    /// "AUJOURD'HUI", "HIER" or "LUN. 3 NOV."
    static func dayTitle(_ key: String) -> String {
        let today = DayKey.today()
        if key == today { return "Aujourd'hui" }
        if key == DayKey.adding(-1, to: today) { return "Hier" }
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    static func longDate(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: d).capitalized(with: fr)
    }

    static func shortWeekday(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "EEEEE"
        return f.string(from: d).uppercased()
    }

    static func relative(_ d: Date?) -> String {
        guard let d else { return "jamais" }
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86400 { return "il y a \(Int(s / 3600)) h" }
        return "il y a \(Int(s / 86400)) j"
    }
}
