import SwiftUI

/// Circular score gauge (Sommeil / Récupération / Effort).
struct ScoreRing: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 9
    var size: CGFloat = 100
    var valueText: String
    var suffix: String = ""
    var valueSize: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(valueText).font(WFont.number(valueSize, weight: .bold))
                if !suffix.isEmpty { Text(suffix).font(WFont.number(valueSize * 0.55, weight: .bold)) }
            }
            .foregroundColor(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, lineWidth + 4)
        }
        .frame(width: size, height: size)
    }
}

/// Ring + tappable uppercase label with chevron, as on the WHOOP home screen.
struct HomeRing: View {
    var title: String
    var progress: Double
    var color: Color
    var value: String
    var suffix: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ScoreRing(progress: progress, color: color, valueText: value, suffix: suffix)
                HStack(spacing: 4) {
                    Text(title).wLabel(12.5)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Section header "ACTIVITÉS DU JOUR" style.
struct SectionLabel: View {
    var text: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(text).wLabel(13.5)
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// Colored rounded badge used for activities (sleep / workouts).
struct ActivityBadge: View {
    var icon: String
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold))
            Text(value).font(WFont.number(25, weight: .bold))
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(width: 108, height: 46)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
    }
}

/// One row of "ACTIVITÉS DU JOUR".
struct ActivityRow: View {
    var icon: String
    var value: String
    var title: String
    var start: String
    var end: String
    var color: Color

    var body: some View {
        HStack(spacing: 14) {
            ActivityBadge(icon: icon, value: value, color: color)
            Text(title).wLabel(14, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                Text(start)
                Text(end)
            }
            .font(WFont.number(16, weight: .medium))
            .foregroundColor(Theme.textSecondary)
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 34)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardInner.opacity(0.55)))
    }
}

/// Dark rounded button with icon and two-line uppercase text.
struct CardButton: View {
    var icon: String
    var text: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20, weight: .regular)).foregroundColor(.white)
                Text(text).wLabel(12.5).multilineTextAlignment(.leading).lineSpacing(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardInner.opacity(0.55)))
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(Theme.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).wLabel(12, weight: .bold).lineLimit(2).minimumScaleFactor(0.8)
                if let baseline {
                    Text("Moy. 30 j : \(baseline)").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textTertiary)
                }
            }
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let up = trendUp {
                    Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 9))
                        .foregroundColor(good == nil ? Theme.textSecondary : (good! ? Theme.recoveryGreen : Theme.recoveryRed))
                }
                Text(value).font(WFont.number(24, weight: .bold)).foregroundColor(.white)
                if !unit.isEmpty { Text(unit).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).wLabel(10.5, weight: .bold, color: Theme.textSecondary, tracking: 1.2).lineLimit(2).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(WFont.number(26, weight: .bold)).foregroundColor(color)
                if !unit.isEmpty { Text(unit).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textSecondary) }
            }
            if let caption { Text(caption).font(.system(size: 11)).foregroundColor(Theme.textTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardGradient))
    }
}

/// Simple bar chart (last N days) without the Charts framework.
struct MiniBars: View {
    var values: [Double?]
    var labels: [String]
    var color: (Double) -> Color
    var maxValue: Double
    var format: (Double) -> String = { Fmt.dec1($0) }
    var height: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 5) {
                    Text(v.map(format) ?? "")
                        .font(WFont.number(11, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(v.map(color) ?? Theme.track)
                        .frame(height: max(3, CGFloat((v ?? 0) / max(maxValue, 0.001)) * height))
                    Text(i < labels.count ? labels[i] : "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 40)
    }
}

/// Hypnogram: stage lanes over time.
struct Hypnogram: View {
    var stages: [StageSegment]

    private let order: [SleepStage] = [.wake, .rem, .light, .deep]

    var body: some View {
        GeometryReader { geo in
            let start = stages.first?.start ?? 0
            let end = stages.last?.end ?? 1
            let span = CGFloat(max(1, end - start))
            let laneH = geo.size.height / CGFloat(order.count)
            ZStack(alignment: .topLeading) {
                ForEach(0..<order.count, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(0.04))
                        .frame(height: 1)
                        .offset(y: laneH * CGFloat(i) + laneH / 2)
                }
                ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                    let lane = order.firstIndex(of: s.stage) ?? 2
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.stageColor(s.stage))
                        .frame(width: max(1.5, CGFloat(s.end - s.start) / span * geo.size.width), height: laneH * 0.62)
                        .offset(x: CGFloat(s.start - start) / span * geo.size.width, y: laneH * CGFloat(lane) + laneH * 0.19)
                }
            }
        }
    }
}

/// Line chart for a series of values (e.g. heart rate trace).
struct LineTrace: View {
    var values: [Double?]
    var color: Color
    var minY: Double? = nil
    var maxY: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let present = values.compactMap { $0 }
            let lo = minY ?? (present.min() ?? 0)
            let hi = maxY ?? (present.max() ?? 1)
            let span = max(hi - lo, 1)
            Path { p in
                var started = false
                for (i, v) in values.enumerated() {
                    guard let v else { started = false; continue }
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1))
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                    if started { p.addLine(to: CGPoint(x: x, y: y)) } else { p.move(to: CGPoint(x: x, y: y)); started = true }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Horizontal zone breakdown (HR zones 1–5).
struct ZoneBars: View {
    var seconds: [Int]
    var colors: [Color] = [Color(hex: 0x6D7C8C), Color(hex: 0x56A0E8), Color(hex: 0x3BC08E), Color(hex: 0xF0C33C), Color(hex: 0xF07B2E), Color(hex: 0xE8333F)]

    var body: some View {
        let total = max(1, seconds.dropFirst().reduce(0, +))
        VStack(spacing: 10) {
            ForEach((1...5).reversed(), id: \.self) { z in
                let s = z < seconds.count ? seconds[z] : 0
                HStack(spacing: 10) {
                    Text("Zone \(z)").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.textSecondary).frame(width: 52, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(colors[z]).frame(width: g.size.width * CGFloat(s) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                    Text(Fmt.hm(Double(s))).font(WFont.number(14, weight: .semibold)).foregroundColor(.white).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

/// Background used by every screen.
struct ScreenBackground: View {
    var body: some View { Theme.background.ignoresSafeArea() }
}

/// Standard sheet/detail header: close button + centered uppercase title.
struct SheetHeader: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title).wLabel(15, weight: .bold, tracking: 2.2).multilineTextAlignment(.center).padding(.horizontal, 56)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// Bottom pill button "ENREGISTRER".
struct OutlineButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).wLabel(15, weight: .bold, color: Theme.accentBlue, tracking: 2.4)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Capsule().fill(Color.black.opacity(0.25)))
                .overlay(Capsule().stroke(Theme.accentBlue, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
