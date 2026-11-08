import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Visual language modelled on the WHOOP app: deep slate gradient, rounded dark cards,
/// uppercase tracked labels, condensed numerals.
enum Theme {
    static let bgTop = Color(hex: 0x29313A)
    static let bgBottom = Color(hex: 0x0B0D10)
    static let card = Color(hex: 0x2B3138)
    static let cardTop = Color(hex: 0x323940)
    static let cardBottom = Color(hex: 0x262B31)
    static let cardInner = Color(hex: 0x3A4148)
    static let track = Color(hex: 0x30373E)
    static let separator = Color.white.opacity(0.08)
    static let text = Color.white
    static let textSecondary = Color(hex: 0x9AA3AC)
    static let textTertiary = Color(hex: 0x6C757E)

    static let sleep = Color(hex: 0x8DA6BE)
    static let sleepBadge = Color(hex: 0x8197AF)
    static let strain = Color(hex: 0x2E8DEB)
    static let strainBadge = Color(hex: 0x3D8FE9)
    static let recoveryGreen = Color(hex: 0x16EC06)
    static let recoveryYellow = Color(hex: 0xF7DC3A)
    static let recoveryRed = Color(hex: 0xFF2A3B)
    static let accentBlue = Color(hex: 0x6FA8E8)
    static let alarmOrange = Color(hex: 0xC88234)
    static let teal = Color(hex: 0x59CFC1)
    static let coachPurple = Color(hex: 0x8A7CF0)

    static let deep = Color(hex: 0xB070F0)
    static let rem = Color(hex: 0x6CC6F5)
    static let light = Color(hex: 0x7F9BB6)
    static let awake = Color(hex: 0xE8E8E8)

    static func recoveryColor(_ score: Double?) -> Color {
        guard let s = score else { return textSecondary }
        switch Recovery.zone(s) {
        case .red: return recoveryRed
        case .yellow: return recoveryYellow
        case .green: return recoveryGreen
        }
    }

    static let background = LinearGradient(colors: [bgTop, Color(hex: 0x1A1F25), bgBottom],
                                           startPoint: .top, endPoint: .bottom)
    static let cardGradient = LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)

    static func stageColor(_ s: SleepStage) -> Color {
        switch s {
        case .wake: return awake
        case .light: return light
        case .deep: return deep
        case .rem: return rem
        }
    }
}

/// Typography: condensed numerals (Barlow Semi Condensed, SIL OFL) + system text.
enum WFont {
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch weight {
        case .bold, .heavy, .black: return .custom("BarlowSemiCondensed-Bold", size: size)
        case .medium, .regular, .light, .thin, .ultraLight: return .custom("BarlowSemiCondensed-Medium", size: size)
        default: return .custom("BarlowSemiCondensed-SemiBold", size: size)
        }
    }

    static func label(_ size: CGFloat = 13, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold) }
}

extension View {
    /// Uppercase, tracked label in the WHOOP style.
    func wLabel(_ size: CGFloat = 13, weight: Font.Weight = .bold, color: Color = Theme.text, tracking: CGFloat = 1.6) -> some View {
        self.font(WFont.label(size, weight: weight))
            .tracking(tracking)
            .foregroundColor(color)
            .textCase(.uppercase)
    }

    func wCard(radius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.cardGradient))
    }
}

/// French number / time formatting.
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
