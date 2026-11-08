import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Visual language of the WHOOP app, measured on screenshots of the real app (iPhone, 393 pt):
/// slate-to-black background, flat dark cards, light uppercase labels with a little tracking,
/// DIN-like numerals and a geometric text face.
enum Theme {
    // MARK: Background
    static let bgTop = Color(hex: 0x2A3137)
    static let bgBottom = Color(hex: 0x08090B)
    static let background = LinearGradient(stops: [
        .init(color: bgTop, location: 0),
        .init(color: Color(hex: 0x1C2126), location: 0.30),
        .init(color: Color(hex: 0x13161A), location: 0.62),
        .init(color: bgBottom, location: 1),
    ], startPoint: .top, endPoint: .bottom)

    // MARK: Surfaces
    static let cardTop = Color(hex: 0x2E3236)
    static let cardBottom = Color(hex: 0x272A2E)
    static let card = Color(hex: 0x2B2F33)
    static let cardGradient = LinearGradient(colors: [cardTop, cardBottom], startPoint: .top, endPoint: .bottom)
    /// Tall cards fade towards the background (sleep breakdown, metric cards).
    static let cardFade = LinearGradient(colors: [Color(hex: 0x2D3135), Color(hex: 0x1A1D20)], startPoint: .top, endPoint: .bottom)
    /// Rows inside a card ("ACTIVITÉS DU JOUR").
    static let row = Color(hex: 0x424448)
    /// Buttons inside a card ("AJOUTER UNE ACTIVITÉ").
    static let control = Color(hex: 0x46474A)
    static let pill = Color(hex: 0x474C50)
    static let pillOuter = Color(hex: 0x30373D)
    static let track = Color(hex: 0x363B40)
    static let separator = Color(hex: 0x35393D)
    static let legendBox = Color(hex: 0x0A0B0D)
    // Kept for older call sites.
    static let cardInner = row

    // MARK: Text
    static let text = Color.white
    static let textSecondary = Color(hex: 0xA3A5A8)
    static let textTertiary = Color(hex: 0x8A8D91)
    static let textMuted = Color(hex: 0x6E7175)

    // MARK: Scores (sampled)
    static let sleep = Color(hex: 0x84A0B8)
    static let sleepBadge = Color(hex: 0x849FBA)
    static let strain = Color(hex: 0x4091E2)
    static let strainBadge = Color(hex: 0x4290E2)
    static let recoveryGreen = Color(hex: 0x16EC06)
    static let recoveryYellow = Color(hex: 0xFAE049)
    static let recoveryRed = Color(hex: 0xFF2A3B)
    static let accentBlue = Color(hex: 0x77A9DE)
    static let alarmOrange = Color(hex: 0xD08A3A)
    static let teal = Color(hex: 0x59CFC1)
    static let coachPurple = Color(hex: 0x8A7CF0)

    // MARK: States (sleep / recovery breakdown)
    static let insufficient = Color(hex: 0xF2AB47)
    static let sufficient = Color(hex: 0x929395)
    static let optimal = Color(hex: 0x6FEEA5)
    static let segmentOff = Color(hex: 0x3E4044)

    // MARK: Sleep stages (sampled)
    static let awake = Color(hex: 0xC8C8C8)
    static let light = Color(hex: 0xA5A3EE)
    static let deep = Color(hex: 0xED9AF6)
    static let rem = Color(hex: 0xA25EE7)
    static let restorative = LinearGradient(colors: [rem, deep], startPoint: .bottomLeading, endPoint: .topTrailing)

    // MARK: Heart-rate zones (0…5)
    static let zones: [Color] = [Color(hex: 0x6D7378), Color(hex: 0x8FB3D1), Color(hex: 0x4FA3E8),
                                 Color(hex: 0x3DCB8A), Color(hex: 0xF5A43A), Color(hex: 0xF0453A)]
    static func zoneColor(_ z: Int) -> Color { zones[max(0, min(5, z))] }

    static func recoveryColor(_ score: Double?) -> Color {
        guard let s = score else { return textSecondary }
        switch Recovery.zone(s) {
        case .red: return recoveryRed
        case .yellow: return recoveryYellow
        case .green: return recoveryGreen
        }
    }

    static func stageColor(_ s: SleepStage) -> Color {
        switch s {
        case .wake: return awake
        case .light: return light
        case .deep: return deep
        case .rem: return rem
        }
    }

    // MARK: Layout
    static let side: CGFloat = 16
    static let radius: CGFloat = 16
}

/// Typography.
/// - `label`: uppercase tracked labels — Montserrat (SIL OFL), the closest free match to the
///   geometric face WHOOP uses for its labels.
/// - `text`: sentences and titles — Figtree (SIL OFL).
/// - `number`: numerals — Barlow Semi Condensed (SIL OFL), DIN-like like WHOOP's figures.
/// Fixed sizes (no Dynamic Type), as in the WHOOP app, so layouts stay exact.
enum WFont {
    static func label(_ size: CGFloat = 11.5, weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Montserrat-Bold"
        case .semibold: name = "Montserrat-SemiBold"
        default: name = "Montserrat-Medium"
        }
        return .custom(name, fixedSize: size)
    }

    static func text(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Figtree-Bold"
        case .semibold: name = "Figtree-SemiBold"
        case .medium: name = "Figtree-Medium"
        default: name = "Figtree-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "BarlowSemiCondensed-Bold"
        case .semibold: name = "BarlowSemiCondensed-SemiBold"
        default: name = "BarlowSemiCondensed-Medium"
        }
        return .custom(name, fixedSize: size)
    }

    /// Screen and section titles ("Ma journée").
    static func title(_ size: CGFloat = 20) -> Font { text(size, weight: .semibold) }

    /// The big score inside the detail rings ("76%").
    static func display(_ size: CGFloat) -> Font { text(size, weight: .bold) }
}

extension View {
    /// Uppercase tracked label in the WHOOP style. `tracking` is in points (default 6 % of the size).
    func wLabel(_ size: CGFloat = 11.5, weight: Font.Weight = .semibold, color: Color = Theme.text, tracking: CGFloat? = nil) -> some View {
        self.font(WFont.label(size, weight: weight))
            .tracking(tracking ?? size * 0.06)
            .foregroundColor(color)
            .textCase(.uppercase)
    }

    func wCard(radius: CGFloat = Theme.radius, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.cardGradient))
    }
}

/// Light haptic feedback on taps, as in the WHOOP app.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func softTap() { soft.impactOccurred(intensity: 0.7) }
    static func select() { selection.selectionChanged() }
    static func success() { notify.notificationOccurred(.success) }
}

/// Buttons that dim and shrink slightly while pressed (WHOOP-like feel), with a light haptic.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed && haptic { Haptics.softTap() }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
