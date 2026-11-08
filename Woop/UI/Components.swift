import SwiftUI

// MARK: - Rings

/// "76%" / "12,8": DIN-like figures with a smaller percent sign.
struct ScoreText: View {
    var value: String
    var suffix: String = ""
    var size: CGFloat
    var color: Color = .white
    var font: (CGFloat) -> Font = { WFont.number($0, weight: .bold) }
    var suffixScale: CGFloat = 0.62

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            Text(value).font(font(size))
            if !suffix.isEmpty { Text(suffix).font(font(size * suffixScale)) }
        }
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }
}

/// Circular score gauge of the home screen (Sommeil / Récupération / Effort): 86 pt, 6 pt stroke,
/// flat ends, filled clockwise from 12 o'clock.
struct ScoreRing: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 86
    var valueText: String
    var suffix: String = ""
    var valueSize: CGFloat = 27.5
    /// White tick across the ring (the day's optimal strain), 0…1.
    var marker: Double? = nil
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(Theme.track, lineWidth: lineWidth)
            Circle().inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.0005, min(1, shown)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if let marker {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: lineWidth + 1)
                    .offset(y: -(size / 2 - lineWidth / 2))
                    .rotationEffect(.degrees(360 * min(1, max(0, marker))))
            }
            ScoreText(value: valueText, suffix: suffix, size: valueSize)
                .padding(.horizontal, lineWidth + 5)
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = progress } }
        .onChange(of: progress) { p in withAnimation(.easeOut(duration: 0.6)) { shown = p } }
    }
}

/// Large ring at the top of the Sommeil / Récupération / Effort screens (254 pt, 12 pt stroke):
/// wordmark, big score, uppercase caption.
struct BigScoreRing: View {
    var progress: Double
    var color: Color
    var value: String
    var suffix: String = ""
    var caption: String
    var size: CGFloat = 254
    var lineWidth: CGFloat = 12
    /// Optional band drawn just outside the ring (optimal strain range), 0…1.
    var band: ClosedRange<Double>? = nil
    var marker: Double? = nil
    /// Page dashes under the caption (ring carousel).
    var pages: (count: Int, index: Int)? = nil
    @State private var shown: Double = 0

    /// Room left outside the ring for the optimal band.
    private var pad: CGFloat { band == nil ? 0 : 7 }

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2 + pad).stroke(Theme.track, lineWidth: lineWidth)
            Circle().inset(by: lineWidth / 2 + pad)
                .trim(from: 0, to: max(0.0005, min(1, shown)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if let band {
                Circle().inset(by: 1.5)
                    .trim(from: max(0, band.lowerBound), to: min(1, band.upperBound))
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let marker {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2.5, height: lineWidth + 2)
                    .offset(y: -(size / 2 - lineWidth / 2 - pad))
                    .rotationEffect(.degrees(360 * min(1, max(0, marker))))
            }
            // Positions measured on the WHOOP sleep ring (centre-relative, 254 pt ring).
            Wordmark(size: 17, color: Color(hex: 0x909498)).offset(y: -58)
            ScoreText(value: value, suffix: suffix, size: 68, font: { WFont.display($0) }, suffixScale: 0.62)
                .padding(.horizontal, 34)
                .offset(y: -6)
            Text(caption).wLabel(12.3, tracking: 0.7).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 40)
                .offset(y: 41)
            if let pages { PageDashes(count: pages.count, index: pages.index).offset(y: 67) }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = progress } }
        .onChange(of: progress) { p in withAnimation(.easeOut(duration: 0.6)) { shown = p } }
    }
}

/// Three short dashes under the big ring (pages).
struct PageDashes: View {
    var count: Int
    var index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == index ? Color(hex: 0x8E8F92) : Color(hex: 0x3A3D41))
                    .frame(width: 20, height: 3.5)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }
}

/// "WOOP" in the thin geometric style of the wordmark.
struct Wordmark: View {
    var size: CGFloat = 17
    var color: Color = .white

    var body: some View {
        Text("WOOP")
            .font(.system(size: size, weight: .light))
            .tracking(size * 0.24)
            .foregroundColor(color)
    }
}

// MARK: - Rows & buttons

/// Colored rounded badge used for activities (sleep / workouts): 93 × 39 pt.
struct ActivityBadge: View {
    var icon: String
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular))
            Text(value).font(WFont.number(17.5, weight: .bold))
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(width: 93, height: 39)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
    }
}

/// One row of "ACTIVITÉS DU JOUR" (55 pt high).
struct ActivityRow: View {
    var icon: String
    var value: String
    var title: String
    var start: String
    var end: String
    var color: Color

    var body: some View {
        HStack(spacing: 0) {
            ActivityBadge(icon: icon, value: value, color: color)
            Text(title).wLabel(12.3)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.leading, 15)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 7) {
                Text(start)
                Text(end)
            }
            .font(WFont.number(11.5, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            RoundedRectangle(cornerRadius: 1.2).fill(color).frame(width: 2.3, height: 27.5)
                .padding(.leading, 9)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 55)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.row))
    }
}

/// Dark rounded button with icon and two-line uppercase text ("AJOUTER UNE ACTIVITÉ").
struct CardButton: View {
    var icon: String
    var text: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundColor(.white)
                    .frame(width: 18)
                Text(text).wLabel(10.4).multilineTextAlignment(.leading).lineSpacing(2)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.control))
        }
        .buttonStyle(.pressable)
    }
}

/// A metric tile row: icon, label, value with unit and a trend vs. the 30-day average.
struct MetricRow: View {
    var icon: String
    var title: String
    var value: String
    var unit: String
    var baseline: String?
    var trendUp: Bool?
    var good: Bool?

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundColor(Theme.textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).wLabel(11.5).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                if let baseline {
                    Text("Moy. 30 j : \(baseline)").font(WFont.text(12, weight: .medium)).foregroundColor(Theme.textTertiary)
                }
            }
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let up = trendUp { TrendArrow(up: up, good: good) }
                Text(value).font(WFont.number(21, weight: .bold)).foregroundColor(.white)
                if !unit.isEmpty { Text(unit).font(WFont.text(11, weight: .medium)).foregroundColor(Theme.textSecondary) }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
    }
}

/// Small ▲ / ▼ vs. the usual value (green good, orange worse, grey neutral).
struct TrendArrow: View {
    var up: Bool
    var good: Bool?
    var size: CGFloat = 8

    var body: some View {
        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: size))
            .foregroundColor(good == nil ? Theme.textSecondary : (good! ? Theme.optimal : Theme.insufficient))
    }
}

/// Small key/value tile used in detail screens.
struct StatTile: View {
    var title: String
    var value: String
    var unit: String = ""
    var caption: String? = nil
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).wLabel(10.4, color: Theme.textSecondary).lineLimit(2).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(WFont.number(23, weight: .bold)).foregroundColor(color)
                if !unit.isEmpty { Text(unit).font(WFont.text(11.5, weight: .medium)).foregroundColor(Theme.textSecondary) }
            }
            if let caption { Text(caption).font(WFont.text(11.5)).foregroundColor(Theme.textTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardGradient))
    }
}

// MARK: - Qualitative states (Insuffisant / Suffisant / Optimal)

enum QualityState: Int {
    case insufficient = 0, sufficient = 1, optimal = 2

    var color: Color {
        switch self {
        case .insufficient: return Theme.insufficient
        case .sufficient: return Theme.sufficient
        case .optimal: return Theme.optimal
        }
    }

    var label: String {
        switch self {
        case .insufficient: return "Insuffisant"
        case .sufficient: return "Suffisant"
        case .optimal: return "Optimal"
        }
    }

    /// Higher is better, with the two thresholds of the WHOOP sleep categories.
    static func higher(_ v: Double?, sufficient: Double, optimal: Double) -> QualityState? {
        guard let v else { return nil }
        if v >= optimal { return .optimal }
        if v >= sufficient { return .sufficient }
        return .insufficient
    }

    static func lower(_ v: Double?, optimal: Double, sufficient: Double) -> QualityState? {
        guard let v else { return nil }
        if v <= optimal { return .optimal }
        if v <= sufficient { return .sufficient }
        return .insufficient
    }
}

/// Three short segments, the one of the current state lit (63 × 4 pt).
struct SegmentBar: View {
    var state: QualityState?

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(state?.rawValue == i ? state!.color : Theme.segmentOff)
                    .frame(width: 19.5, height: 4)
            }
        }
    }
}

/// "▬ Insuffisant ▬ Suffisant ▬ Optimal" in a dark box.
struct QualityLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([QualityState.insufficient, .sufficient, .optimal], id: \.rawValue) { s in
                HStack(spacing: 9) {
                    Capsule().fill(s.color).frame(width: 11.5, height: 4)
                    Text(s.label).font(WFont.text(11.5, weight: .medium)).foregroundColor(Color(hex: 0xB4B4B6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 31)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.legendBox))
    }
}

/// One line of a breakdown card: icon, label, state bar, value.
struct BreakdownRow: View {
    var icon: String
    var title: String
    var value: String
    var state: QualityState?
    var trend: (up: Bool, good: Bool?)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundColor(Color(hex: 0x8E8F93))
                .frame(width: 22)
            Text(title).wLabel(12)
                .lineLimit(2).minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
            Spacer(minLength: 8)
            if state != nil || trend == nil { SegmentBar(state: state) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let trend { TrendArrow(up: trend.up, good: trend.good) }
                Text(value).font(WFont.number(21.5, weight: .bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .frame(minHeight: 63)
    }
}

/// Card with a small pointer at the top (points to the ring above).
struct PointerCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(PointerCardShape().fill(Theme.cardFade))
            .padding(.top, 7)
    }
}

struct PointerCardShape: Shape {
    var radius: CGFloat = 16
    var pointer = CGSize(width: 22, height: 7)

    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        let mid = r.midX
        p.move(to: CGPoint(x: mid - pointer.width / 2, y: r.minY + 0.5))
        p.addLine(to: CGPoint(x: mid, y: r.minY - pointer.height))
        p.addLine(to: CGPoint(x: mid + pointer.width / 2, y: r.minY + 0.5))
        p.closeSubpath()
        return p
    }
}

// MARK: - Sleep stage bar

/// Stage share bar: hatched capsule track, filled share, dashed box on the usual range.
struct HatchedBar: View {
    var fraction: Double
    var color: Color
    var usual: ClosedRange<Double>?
    var height: CGFloat = 15

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                    ctx.fill(track, with: .color(Color(hex: 0x2A2B2F)))
                    ctx.clip(to: track)
                    var x: CGFloat = -size.height
                    var stripes = Path()
                    while x < size.width + size.height {
                        stripes.move(to: CGPoint(x: x, y: size.height))
                        stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 5.5
                    }
                    ctx.stroke(stripes, with: .color(Color(hex: 0x3B3C40)), lineWidth: 2)
                }
                .frame(height: height)
                if let usual {
                    let lo = CGFloat(max(0, min(1, usual.lowerBound))) * w
                    let hi = CGFloat(max(0, min(1, usual.upperBound))) * w
                    Rectangle().fill(Color(hex: 0x48494D).opacity(0.85))
                        .frame(width: max(8, hi - lo), height: height + 6)
                        .overlay(Rectangle().stroke(Color(hex: 0xB1B2B5), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])))
                        .offset(x: lo)
                }
                Capsule().fill(color)
                    .frame(width: max(height * 0.7, CGFloat(max(0, min(1, fraction))) * w), height: height)
            }
            .frame(height: g.size.height)
        }
        .frame(height: height + 6)
    }
}

// MARK: - Structure

/// Background used by every screen.
struct ScreenBackground: View {
    var body: some View { Theme.background.ignoresSafeArea() }
}

/// Section label "ACTIVITÉS DU JOUR".
struct SectionLabel: View {
    var text: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(text).wLabel(11.8)
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// "Sommeil des dernières nuits" + "Aujourd'hui par rapport aux 30 jours précédents" + MODIFIER.
struct SectionTitle: View {
    var title: String
    var subtitle: Bool = true
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title).font(WFont.title(20)).foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if let onEdit {
                    Button(action: onEdit) {
                        HStack(spacing: 7) {
                            Text("Modifier").wLabel(11, color: Color(hex: 0xF2F3F4))
                            Image(systemName: "pencil").font(.system(size: 13, weight: .regular)).foregroundColor(.white)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.pressable)
                }
            }
            if subtitle {
                (Text("Aujourd'hui ").foregroundColor(.white)
                 + Text("par rapport aux 30 jours précédents").foregroundColor(Color(hex: 0xBBBCBD)))
                    .font(WFont.text(12.5, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

/// Standard sheet header: close button + centered uppercase title.
struct SheetHeader: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title).wLabel(12.9, tracking: 0.9).multilineTextAlignment(.center).lineSpacing(6).padding(.horizontal, 70)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 19, weight: .regular)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                Spacer()
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// Bottom pill button "ENREGISTRER".
struct OutlineButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).wLabel(12.3, color: Theme.accentBlue, tracking: 0.9)
                .frame(maxWidth: .infinity, minHeight: 49)
                .background(Capsule().fill(Color(hex: 0x0E1114)))
                .overlay(Capsule().stroke(Theme.accentBlue, lineWidth: 2))
        }
        .buttonStyle(.pressable)
    }
}

/// Filled blue capsule ("COMMENCER L'ACTIVITÉ").
struct PrimaryButton: View {
    var title: String
    var color: Color = Theme.strainBadge
    var textColor: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).wLabel(13.7, color: textColor, tracking: 0.6)
                .frame(maxWidth: .infinity, minHeight: 53)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.pressable)
    }
}

/// "(i)" button.
struct InfoButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle").font(.system(size: 17, weight: .light)).foregroundColor(Color(hex: 0x93979A))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.pressable)
    }
}

/// Simple bar chart (last N days) without the Charts framework.
struct MiniBars: View {
    var values: [Double?]
    var labels: [String]
    var color: (Double) -> Color
    var maxValue: Double
    var format: (Double) -> String = { Fmt.dec1($0) }
    var height: CGFloat = 110

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 6) {
                    Text(v.map(format) ?? "")
                        .font(WFont.number(11, weight: .semibold))
                        .foregroundColor(i == values.count - 1 ? .white : Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(v.map(color) ?? Theme.track)
                        .opacity(i == values.count - 1 ? 1 : 0.75)
                        .frame(height: max(3, CGFloat((v ?? 0) / max(maxValue, 0.001)) * height))
                    Text(i < labels.count ? labels[i] : "")
                        .font(WFont.label(9.5, weight: .semibold))
                        .foregroundColor(i == values.count - 1 ? .white : Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 40)
    }
}

/// Horizontal zone breakdown (HR zones 1–5), WHOOP style: zone, bar, share and time.
struct ZoneBars: View {
    var seconds: [Int]

    var body: some View {
        let total = max(1, seconds.dropFirst().reduce(0, +))
        VStack(spacing: 13) {
            ForEach((1...5).reversed(), id: \.self) { z in
                let s = z < seconds.count ? seconds[z] : 0
                HStack(spacing: 10) {
                    Text("\(z)").font(WFont.number(15, weight: .bold)).foregroundColor(.white).frame(width: 14)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.zoneColor(z))
                                .frame(width: max(s > 0 ? 6 : 0, g.size.width * CGFloat(s) / CGFloat(total)))
                        }
                    }
                    .frame(height: 9)
                    Text("\(Int((Double(s) / Double(total) * 100).rounded())) %")
                        .font(WFont.number(13, weight: .semibold)).foregroundColor(Theme.textSecondary).frame(width: 40, alignment: .trailing)
                    Text(Fmt.hm(Double(s))).font(WFont.number(15, weight: .bold)).foregroundColor(.white).frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}
