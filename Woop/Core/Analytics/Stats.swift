import Foundation

/// Small numeric helpers shared by the analyzers. All return nil on empty input rather
/// than inventing a value.
enum Stats {
    static func mean(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    static func median(_ v: [Double]) -> Double? { percentile(v, 50) }

    /// Linear-interpolated percentile (0…100).
    static func percentile(_ v: [Double], _ p: Double) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        if s.count == 1 { return s[0] }
        let pos = max(0, min(1, p / 100)) * Double(s.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        return s[lo] + (pos - Double(lo)) * (s[hi] - s[lo])
    }

    static func std(_ v: [Double]) -> Double? {
        guard v.count >= 2, let m = mean(v) else { return nil }
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
    }

    /// Mean absolute deviation around the mean.
    static func meanAbsDev(_ v: [Double]) -> Double? {
        guard let m = mean(v) else { return nil }
        return v.reduce(0) { $0 + abs($1 - m) } / Double(v.count)
    }

    /// Mean after clamping to the [lo, hi] percentiles (robust to a single outlier night).
    static func winsorizedMean(_ v: [Double], lo: Double = 10, hi: Double = 90) -> Double? {
        guard let a = percentile(v, lo), let b = percentile(v, hi) else { return nil }
        return mean(v.map { min(max($0, a), b) })
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
}

/// Calendar helpers. Day keys are LOCAL calendar dates "yyyy-MM-dd".
enum DayKey {
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func key(unix: Int) -> String { key(Date(timeIntervalSince1970: TimeInterval(unix))) }

    static func date(_ key: String) -> Date? { formatter.date(from: key) }

    /// Local midnight starting the day `key`, as unix seconds.
    static func startUnix(_ key: String) -> Int? {
        guard let d = date(key) else { return nil }
        return Int(calendar.startOfDay(for: d).timeIntervalSince1970)
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key), let n = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return Self.key(n)
    }

    static func today() -> String { key(Date()) }

    /// Minutes since local midnight for a unix time.
    static func minuteOfDay(unix: Int) -> Int {
        let d = Date(timeIntervalSince1970: TimeInterval(unix))
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
