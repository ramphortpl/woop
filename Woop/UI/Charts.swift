import SwiftUI

// Charts drawn with Canvas (one draw call per chart, no per-point views) so scrolling stays fluid.

// MARK: - Axis helpers

enum ChartAxis {
    /// Five evenly spaced heart-rate gridlines with a round step covering the data
    /// (30 · 50 · 70 · 90 · 110 for a typical night, as in WHOOP).
    static func hrTicks(_ values: [Double]) -> [Double] {
        guard let mn = values.min(), let mx = values.max() else { return [30, 50, 70, 90, 110] }
        for step in [20.0, 25, 30, 40, 50] {
            for lo in [30.0, 40, 50, 60, 20, 10, 0] where lo <= mn - 2 && lo + 4 * step >= mx + 2 {
                return (0...4).map { lo + Double($0) * step }
            }
        }
        let lo = max(0, (mn / 10).rounded(.down) * 10)
        let step = max(10, ((mx - lo) / 4 / 10).rounded(.up) * 10)
        return (0...4).map { lo + Double($0) * step }
    }
}

// MARK: - Sleep heart-rate chart ("HEURES DE SOMMEIL")

/// Heart rate across the night with the sleep window (dashed markers, bedtime and wake labels),
/// the minutes just before and after faded out, and an optional stage highlighted.
struct SleepHRChart: View {
    var points: [HRPoint]
    var start: Int
    var end: Int
    var stages: [StageSegment] = []
    var highlight: SleepStage? = nil
    var color: Color = Theme.sleep

    var pad: Int { max(15 * 60, (end - start) / 12) }

    var body: some View {
        Canvas { ctx, size in
            let x0 = Double(start - pad), x1 = Double(end + pad)
            let ticks = ChartAxis.hrTicks(points.map(\.bpm))
            let lo = ticks.first ?? 30, hi = ticks.last ?? 110
            let top: CGFloat = 8, bottom: CGFloat = size.height - 26
            func X(_ t: Double) -> CGFloat { CGFloat((t - x0) / (x1 - x0)) * size.width }
            func Y(_ v: Double) -> CGFloat { bottom - CGFloat((v - lo) / (hi - lo)) * (bottom - top) }
            let sx = X(Double(start)), ex = X(Double(end))

            // Highlighted stage bands.
            if let h = highlight {
                for s in stages where s.stage == h {
                    let r = CGRect(x: X(Double(s.start)), y: top, width: max(1, X(Double(s.end)) - X(Double(s.start))), height: bottom - top)
                    ctx.fill(Path(r), with: .color(Theme.stageColor(h).opacity(0.16)))
                }
            }

            // Line (broken over gaps) and the area under it inside the window.
            var line = Path()
            var prev: HRPoint?
            for p in points {
                let pt = CGPoint(x: X(Double(p.ts)), y: Y(min(hi, max(lo, p.bpm))))
                if let q = prev, p.ts - q.ts <= 180 { line.addLine(to: pt) } else { line.move(to: pt) }
                prev = p
            }
            var area = Path()
            var lastIn: HRPoint?
            for p in points where p.ts >= start && p.ts <= end {
                let pt = CGPoint(x: X(Double(p.ts)), y: Y(min(hi, max(lo, p.bpm))))
                if let q = lastIn, p.ts - q.ts <= 180 {
                    area.addLine(to: pt)
                } else {
                    if let q = lastIn {
                        area.addLine(to: CGPoint(x: X(Double(q.ts)), y: bottom))
                        area.closeSubpath()
                    }
                    area.move(to: CGPoint(x: pt.x, y: bottom))
                    area.addLine(to: pt)
                }
                lastIn = p
            }
            if let q = lastIn {
                area.addLine(to: CGPoint(x: X(Double(q.ts)), y: bottom))
                area.closeSubpath()
            }
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            // Faded outside the window, full colour inside.
            var outside = ctx
            outside.opacity = 0.32
            outside.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            var inside = ctx
            inside.clip(to: Path(CGRect(x: sx, y: 0, width: ex - sx, height: size.height)))
            inside.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            if let h = highlight {
                for s in stages where s.stage == h {
                    var c = ctx
                    c.clip(to: Path(CGRect(x: X(Double(s.start)), y: 0, width: max(1, X(Double(s.end)) - X(Double(s.start))), height: size.height)))
                    c.stroke(line, with: .color(Theme.stageColor(h)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                }
            }

            // Edge fades.
            let fadeW = min(28, sx)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: fadeW, height: bottom + 1)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x2B2F33), Color(hex: 0x2B2F33).opacity(0)]),
                                           startPoint: .zero, endPoint: CGPoint(x: fadeW, y: 0)))

            // Window markers.
            for x in [sx, ex] {
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: top))
                dash.addLine(to: CGPoint(x: x, y: bottom))
                ctx.stroke(dash, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: bottom - 2.6, width: 5.2, height: 5.2)), with: .color(.white))
            }

            // Y labels (drawn over the line, as in WHOOP).
            for t in ticks {
                ctx.draw(Text("\(Int(t))").font(WFont.number(10.5, weight: .medium)).foregroundColor(Color(hex: 0x919599)),
                         at: CGPoint(x: 21, y: Y(t)), anchor: .trailing)
            }
            // X labels: bedtime and wake.
            let label = { (t: Int) in Text(Fmt.clock24(t)).font(WFont.number(11.5, weight: .bold)).foregroundColor(.white) }
            ctx.draw(label(start), at: CGPoint(x: max(18, sx), y: bottom + 15), anchor: .center)
            ctx.draw(label(end), at: CGPoint(x: min(size.width - 18, ex), y: bottom + 15), anchor: .center)
        }
        .frame(height: 168)
        .accessibilityLabel("Fréquence cardiaque pendant le sommeil")
    }
}

// MARK: - Day heart-rate chart ("Effort de la journée")

struct DayHRChart: View {
    var points: [HRPoint]
    var start: Int
    var end: Int
    var activities: [ActivityRecord] = []
    var sleeps: [SleepSession] = []

    var body: some View {
        Canvas { ctx, size in
            guard end > start else { return }
            let ticks = ChartAxis.hrTicks(points.map(\.bpm))
            let lo = ticks.first ?? 30, hi = ticks.last ?? 190
            let left: CGFloat = 26, top: CGFloat = 22, bottom: CGFloat = size.height - 22
            let w = size.width - left
            func X(_ t: Int) -> CGFloat { left + CGFloat(Double(t - start) / Double(end - start)) * w }
            func Y(_ v: Double) -> CGFloat { bottom - CGFloat((v - lo) / (hi - lo)) * (bottom - top) }

            // Grid.
            for t in ticks {
                var g = Path()
                g.move(to: CGPoint(x: left, y: Y(t)))
                g.addLine(to: CGPoint(x: size.width, y: Y(t)))
                ctx.stroke(g, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                ctx.draw(Text("\(Int(t))").font(WFont.number(10, weight: .medium)).foregroundColor(Theme.textTertiary),
                         at: CGPoint(x: left - 6, y: Y(t)), anchor: .trailing)
            }
            // Sleep and activity bands.
            for s in sleeps {
                let a = max(start, s.start), b = min(end, s.end)
                guard b > a else { continue }
                ctx.fill(Path(CGRect(x: X(a), y: top, width: X(b) - X(a), height: bottom - top)), with: .color(Theme.sleep.opacity(0.13)))
            }
            for act in activities {
                let a = max(start, act.start), b = min(end, act.end)
                guard b > a else { continue }
                let r = CGRect(x: X(a), y: top, width: max(2, X(b) - X(a)), height: bottom - top)
                ctx.fill(Path(r), with: .color(Theme.strain.opacity(0.2)))
                ctx.fill(Path(CGRect(x: r.minX, y: top - 3, width: r.width, height: 3)), with: .color(Theme.strain))
                if r.width > 14 {
                    var icon = ctx.resolve(Image(systemName: Sport.icon(act.sport)))
                    icon.shading = .color(.white)
                    ctx.draw(icon, in: CGRect(x: r.midX - 7, y: top - 21, width: 14, height: 14))
                }
            }
            // Line.
            var line = Path()
            var prev: HRPoint?
            for p in points where p.ts >= start && p.ts <= end {
                let pt = CGPoint(x: X(p.ts), y: Y(min(hi, max(lo, p.bpm))))
                if let q = prev, p.ts - q.ts <= 600 { line.addLine(to: pt) } else { line.move(to: pt) }
                prev = p
            }
            ctx.stroke(line, with: .color(Color(hex: 0xC9D2DB)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            for act in activities {
                var c = ctx
                c.clip(to: Path(CGRect(x: X(act.start), y: 0, width: max(1, X(act.end) - X(act.start)), height: size.height)))
                c.stroke(line, with: .color(Theme.strain), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            // Time labels every 4 hours.
            var t = start - ((start % 3600) + 3600) % 3600 + 3600
            while t < end {
                if DayKey.minuteOfDay(unix: t) % 240 == 0 && X(t) > left + 12 && X(t) < size.width - 12 {
                    ctx.draw(Text(Fmt.clock24(t)).font(WFont.number(10, weight: .semibold)).foregroundColor(Theme.textTertiary),
                             at: CGPoint(x: X(t), y: bottom + 12), anchor: .center)
                }
                t += 3600
            }
        }
        .frame(height: 170)
    }
}

// MARK: - Activity heart-rate chart (zones)

struct ActivityHRChart: View {
    var points: [HRPoint]
    var start: Int
    var end: Int
    var maxHR: Double

    var body: some View {
        Canvas { ctx, size in
            guard end > start else { return }
            let vals = points.map(\.bpm)
            let lo = max(40, ((vals.min() ?? 60) / 10).rounded(.down) * 10 - 10)
            let hi = min(220, ((vals.max() ?? 160) / 10).rounded(.up) * 10 + 10)
            let left: CGFloat = 28, top: CGFloat = 6, bottom: CGFloat = size.height - 20
            func X(_ t: Int) -> CGFloat { left + CGFloat(Double(t - start) / Double(end - start)) * (size.width - left) }
            func Y(_ v: Double) -> CGFloat { bottom - CGFloat((v - lo) / max(1, hi - lo)) * (bottom - top) }

            // Zone bands (50/60/70/80/90 % of max HR).
            for z in 1...5 {
                let a = maxHR * (0.4 + 0.1 * Double(z)), b = z == 5 ? hi : maxHR * (0.5 + 0.1 * Double(z))
                let y0 = Y(min(hi, max(lo, b))), y1 = Y(min(hi, max(lo, a)))
                guard y1 > y0 else { continue }
                ctx.fill(Path(CGRect(x: left, y: y0, width: size.width - left, height: y1 - y0)), with: .color(Theme.zoneColor(z).opacity(0.07)))
                if y1 - y0 > 12 {
                    ctx.draw(Text("Z\(z)").font(WFont.number(9.5, weight: .bold)).foregroundColor(Theme.zoneColor(z).opacity(0.8)),
                             at: CGPoint(x: size.width - 4, y: (y0 + y1) / 2), anchor: .trailing)
                }
            }
            for v in stride(from: (lo / 20).rounded(.up) * 20, through: hi, by: 20) {
                ctx.draw(Text("\(Int(v))").font(WFont.number(10, weight: .medium)).foregroundColor(Theme.textTertiary),
                         at: CGPoint(x: left - 6, y: Y(v)), anchor: .trailing)
            }
            // Line coloured by zone.
            var prev: HRPoint?
            for p in points {
                if let q = prev, p.ts - q.ts <= 180 {
                    var seg = Path()
                    seg.move(to: CGPoint(x: X(q.ts), y: Y(q.bpm)))
                    seg.addLine(to: CGPoint(x: X(p.ts), y: Y(p.bpm)))
                    let z = Strain.zone((p.bpm + q.bpm) / 2, maxHR: maxHR)
                    ctx.stroke(seg, with: .color(Theme.zoneColor(max(1, z))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                prev = p
            }
            ctx.draw(Text(Fmt.clock24(start)).font(WFont.number(10.5, weight: .semibold)).foregroundColor(Theme.textTertiary),
                     at: CGPoint(x: left, y: bottom + 11), anchor: .leading)
            ctx.draw(Text(Fmt.clock24(end)).font(WFont.number(10.5, weight: .semibold)).foregroundColor(Theme.textTertiary),
                     at: CGPoint(x: size.width, y: bottom + 11), anchor: .trailing)
        }
        .frame(height: 160)
    }
}

// MARK: - Trend over recent days

/// Last N days: dots joined by a line, today's value labelled, the 30-day average dashed and the
/// usual range shaded; weekday initials underneath.
struct TrendChart: View {
    var keys: [String]
    var values: [Double?]
    var color: Color
    var format: (Double) -> String
    var average: Double? = nil
    var usual: ClosedRange<Double>? = nil
    var height: CGFloat = 150

    var body: some View {
        Canvas { ctx, size in
            let present = values.compactMap { $0 }
            guard !present.isEmpty else {
                ctx.draw(Text("Pas encore de données").font(WFont.text(13)).foregroundColor(Theme.textTertiary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            var lo = present.min()!, hi = present.max()!
            if let a = average { lo = min(lo, a); hi = max(hi, a) }
            if let u = usual { lo = min(lo, u.lowerBound); hi = max(hi, u.upperBound) }
            let span = max(hi - lo, max(abs(hi) * 0.1, 1))
            lo -= span * 0.18
            hi += span * 0.28
            let top: CGFloat = 22, bottom: CGFloat = size.height - 22
            let n = max(1, values.count)
            let step = size.width / CGFloat(n)
            func X(_ i: Int) -> CGFloat { step * (CGFloat(i) + 0.5) }
            func Y(_ v: Double) -> CGFloat { bottom - CGFloat((v - lo) / (hi - lo)) * (bottom - top) }

            if let u = usual {
                ctx.fill(Path(CGRect(x: 0, y: Y(u.upperBound), width: size.width, height: Y(u.lowerBound) - Y(u.upperBound))),
                         with: .color(Color.white.opacity(0.05)))
            }
            if let a = average {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: Y(a)))
                p.addLine(to: CGPoint(x: size.width, y: Y(a)))
                ctx.stroke(p, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            var line = Path()
            var started = false
            for (i, v) in values.enumerated() {
                guard let v else { started = false; continue }
                let pt = CGPoint(x: X(i), y: Y(v))
                if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
            }
            ctx.stroke(line, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let last = i == values.count - 1
                let r: CGFloat = last ? 4.5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: X(i) - r, y: Y(v) - r, width: 2 * r, height: 2 * r)), with: .color(last ? .white : color))
                if last || values.count <= 7 {
                    ctx.draw(Text(format(v)).font(WFont.number(last ? 12.5 : 10.5, weight: last ? .bold : .semibold))
                                .foregroundColor(last ? .white : Theme.textSecondary),
                             at: CGPoint(x: X(i), y: Y(v) - 12), anchor: .center)
                }
            }
            for (i, k) in keys.enumerated() where values.count <= 14 || i % 5 == 0 || i == keys.count - 1 {
                ctx.draw(Text(values.count <= 14 ? Fmt.shortWeekday(k) : Fmt.dayMonth(k))
                            .font(WFont.label(9.5, weight: .semibold))
                            .foregroundColor(i == keys.count - 1 ? .white : Theme.textTertiary),
                         at: CGPoint(x: X(i), y: size.height - 8), anchor: .center)
            }
        }
        .frame(height: height)
    }
}
