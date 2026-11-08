import SwiftUI

/// Identifiable text for the (i) sheets.
struct InfoItem: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

// MARK: - Sommeil

struct SleepDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String
    @State private var page = 1
    @State private var points: [HRPoint] = []
    @State private var stress: Double?
    @State private var editing = false
    @State private var info: InfoItem?

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: Fmt.dayTitle(date), spacing: 0, scrollTo: app.launchScreen == "sleep2" ? "stats" : nil) {
            pager(d)
            if let s = d.sleep {
                breakdown(d, s).padding(.top, 16)
                SectionTitle(title: "Sommeil des\ndernières nuits", onEdit: { editing = true })
                    .padding(.top, 26)
                    .id("stats")
                VStack(spacing: 14) {
                    ForEach(app.settings.sleepStats) { m in
                        if m == .hoursOfSleep {
                            SleepHoursCard(day: d, sleep: s, points: points) {
                                info = InfoItem(title: m.title, text: m.explanation)
                            }
                        } else {
                            MetricTrendCard(metric: m, date: date)
                        }
                    }
                }
                .padding(.top, 18)
                if !d.naps.isEmpty {
                    CardBox(title: "Siestes") {
                        ForEach(d.naps) { n in
                            HStack {
                                Text("\(Fmt.clock(n.start)) – \(Fmt.clock(n.end))").font(WFont.number(16, weight: .semibold)).foregroundColor(.white)
                                Spacer()
                                Text(Fmt.hm(Double(n.asleepSec))).font(WFont.number(16, weight: .bold)).foregroundColor(Theme.sleep)
                            }
                        }
                    }
                    .padding(.top, 14)
                }
                TileGrid(tiles: [
                    StatTile(title: "Latence d'endormissement", value: "\(s.latencySec / 60)", unit: "min"),
                    StatTile(title: "Perturbations", value: "\(s.disturbances)"),
                    StatTile(title: "Cycles de sommeil", value: "\(s.cycles)"),
                    StatTile(title: "FC moyenne", value: Fmt.int(s.avgHR), unit: "bpm"),
                ])
                .padding(.top, 14)
                Text(s.bandDetected
                     ? "Les phases de sommeil sont estimées à partir de la fréquence cardiaque, de sa variabilité, de la respiration et des mouvements. Ce n'est pas une polysomnographie."
                     : "Nuit détectée à partir des mouvements et de la fréquence cardiaque (l'état de sommeil du bracelet n'était pas disponible).")
                    .font(WFont.text(11.5)).foregroundColor(Theme.textMuted)
                    .padding(.top, 16).padding(.horizontal, 4)
            } else {
                CardBox {
                    Text("Aucun sommeil détecté pour cette journée. Porte ton bracelet la nuit et synchronise-le le matin.")
                        .font(WFont.text(15)).foregroundColor(Theme.textSecondary)
                }
                .padding(.top, 20)
            }
        }
        .task(id: "\(d.sleep?.start ?? 0)-\(d.sleep?.end ?? 0)-\(app.dataVersion)") { await load(d) }
        .sheet(isPresented: $editing) {
            MetricListEditor(title: "Sommeil des dernières nuits", choices: DashboardMetric.sleepChoices,
                             selection: app.settings.sleepStats) { app.settings.sleepStats = $0 }
        }
        .sheet(item: $info) { InfoSheet(title: $0.title, text: $0.text) }
    }

    private func pager(_ d: DayMetrics) -> some View {
        let s = d.sleep
        let asleep = Double(s?.asleepSec ?? 0)
        let need = d.sleepNeedSec ?? 0
        return TabView(selection: $page) {
            BigScoreRing(progress: need > 0 ? asleep / need : 0, color: Theme.sleep,
                         value: s == nil ? "—" : Fmt.hm(asleep), caption: "Heures de sommeil", pages: (3, 0))
                .tag(0)
            BigScoreRing(progress: (d.sleepPerformance ?? 0) / 100, color: Theme.sleep,
                         value: d.sleepPerformance.map { "\(Int($0.rounded()))" } ?? "—",
                         suffix: d.sleepPerformance == nil ? "" : "%", caption: "Votre sommeil", pages: (3, 1))
                .tag(1)
            BigScoreRing(progress: s?.restorativeFraction ?? 0, color: Theme.rem,
                         value: s == nil ? "—" : Fmt.hm(Double(s!.restorativeSec)), caption: "Sommeil réparateur", pages: (3, 2))
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 262)
    }

    private func breakdown(_ d: DayMetrics, _ s: SleepSession) -> some View {
        let need = d.sleepNeedSec ?? 0
        let hoursPct: Double? = need > 0 ? min(100, Double(s.asleepSec) / need * 100) : nil
        let efficiency = s.efficiency * 100
        return PointerCard {
            BreakdownRow(icon: "moon.circle", title: "Heures par rapport aux besoins", value: Fmt.pct(hoursPct),
                         state: .higher(hoursPct, sufficient: 70, optimal: 85))
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "moonphase.waning.crescent", title: "Régularité du sommeil", value: Fmt.pct(d.sleepConsistency),
                         state: .higher(d.sleepConsistency, sufficient: 70, optimal: 80))
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "bed.double", title: "Efficacité du sommeil", value: Fmt.pct(efficiency),
                         state: .higher(efficiency, sufficient: 80, optimal: 90))
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "gauge", title: "Stress élevé pendant le sommeil", value: Fmt.pct(stress),
                         state: .lower(stress, optimal: 5, sufficient: 15))
            QualityLegend().padding(.top, 8)
        }
    }

    private func load(_ d: DayMetrics) async {
        guard let s = d.sleep else { points = []; stress = nil; return }
        let pad = max(15 * 60, (s.end - s.start) / 12)
        let pts = await app.minuteHR(from: s.start - pad, to: s.end + pad)
        points = pts
        stress = Self.highStressShare(pts, sleep: s, rhr: d.rhr ?? s.rhr)
    }

    /// Share of asleep minutes in a sustained high-arousal state: 5-minute mean heart rate at
    /// least 40 % above the night's resting rate (an HR-only proxy of WHOOP's stress monitor).
    static func highStressShare(_ pts: [HRPoint], sleep s: SleepSession, rhr: Double?) -> Double? {
        let inside = pts.filter { $0.ts >= s.start && $0.ts < s.end }
        guard inside.count >= 30 else { return nil }
        let rest = rhr ?? Stats.percentile(inside.map(\.bpm), 5) ?? 55
        let threshold = rest * 1.4
        let stages = s.stages.sorted { $0.start < $1.start }
        var si = 0
        var asleep = 0, high = 0
        var window: [Double] = []
        for p in inside {
            while si < stages.count && stages[si].end <= p.ts { si += 1 }
            let awake = si < stages.count && stages[si].start <= p.ts && stages[si].stage == .wake
            window.append(p.bpm)
            if window.count > 5 { window.removeFirst() }
            guard !awake else { continue }
            asleep += 1
            if window.count == 5 && window.reduce(0, +) / 5 >= threshold { high += 1 }
        }
        guard asleep > 0 else { return nil }
        return Double(high) / Double(asleep) * 100
    }
}

/// "HEURES DE SOMMEIL": hours slept vs. 30 days, heart rate through the night, stage shares
/// against the usual range, restorative sleep.
struct SleepHoursCard: View {
    @EnvironmentObject var app: AppState
    var day: DayMetrics
    var sleep: SleepSession
    var points: [HRPoint]
    var onInfo: () -> Void
    @State private var highlight: SleepStage?

    var body: some View {
        let avg = app.average30(before: day.date) { $0.sleep.map { Double($0.asleepSec) } }
        let usual = app.usualStageShares(before: day.date)
        let total = Double(max(1, sleep.inBedSec))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Heures de sommeil").wLabel(11.5).padding(.top, 2)
                Spacer()
                InfoButton(action: onInfo).offset(x: 6, y: -6)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(Fmt.hm(Double(sleep.asleepSec))).font(WFont.number(24.5, weight: .bold)).foregroundColor(.white)
                if let avg, abs(Double(sleep.asleepSec) - avg) >= 60 {
                    TrendArrow(up: Double(sleep.asleepSec) > avg, good: Double(sleep.asleepSec) > avg, size: 9).padding(.top, 5)
                }
            }
            .padding(.top, 6)
            Text(avg.map { Fmt.hm($0) } ?? "—").font(WFont.number(11.5, weight: .bold)).foregroundColor(Color(hex: 0xBEC0C3))
                .padding(.top, 1)

            if points.isEmpty {
                ZStack {
                    Rectangle().fill(Color.clear)
                    ProgressView().tint(Theme.textSecondary)
                }
                .frame(height: 168)
                .padding(.top, 10)
            } else {
                SleepHRChart(points: points, start: sleep.start, end: sleep.end, stages: sleep.stages, highlight: highlight)
                    .padding(.horizontal, -16)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.25), value: highlight)
            }

            Rectangle().fill(Theme.separator).frame(height: 1).padding(.top, 12)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).stroke(Color(hex: 0xB3B4B7), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                    .frame(width: 11, height: 10)
                Text("Plage habituelle").wLabel(10.4, color: Color(hex: 0xBBBCBF))
                Spacer()
                Text("Durée").wLabel(10.4, color: Color(hex: 0xBDBEC0))
                Text(Fmt.hm(Double(sleep.inBedSec))).font(WFont.number(15, weight: .bold)).foregroundColor(.white)
                    .padding(.leading, 6)
            }
            .padding(.top, 22)

            VStack(spacing: 14) {
                stageRow(.wake, "Réveil", sleep.awakeSec, total, usual[.wake])
                stageRow(.light, "Léger", sleep.lightSec, total, usual[.light])
                stageRow(.deep, "SOL (profond)", sleep.deepSec, total, usual[.deep])
                stageRow(.rem, "SP", sleep.remSec, total, usual[.rem])
            }
            .padding(.top, 18)

            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.restorative).frame(width: 10.5, height: 10.5)
                Text("Sommeil réparateur").wLabel(11.5)
                Spacer()
                Text("\(Int((sleep.restorativeFraction * 100).rounded())) %").font(WFont.text(11.5, weight: .semibold)).foregroundColor(Theme.deep)
                Text(Fmt.hm(Double(sleep.restorativeSec))).font(WFont.number(15, weight: .bold)).foregroundColor(.white)
                    .padding(.leading, 6)
            }
            .padding(.top, 24)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
    }

    private func stageRow(_ stage: SleepStage, _ name: String, _ sec: Int, _ total: Double, _ usual: ClosedRange<Double>?) -> some View {
        let frac = Double(sec) / total
        let on = highlight == stage
        return Button {
            Haptics.select()
            highlight = on ? nil : stage
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 0) {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 2.2)
                        if on { Circle().fill(Theme.stageColor(stage)).padding(4.5) }
                    }
                    .frame(width: 25, height: 25)
                    Text(name).wLabel(11.5).padding(.leading, 10)
                    Text("\(Int((frac * 100).rounded())) %")
                        .font(WFont.text(11.5, weight: .semibold))
                        .foregroundColor(stage == .wake ? Color(hex: 0xC5C6C8) : Theme.stageColor(stage))
                        .padding(.leading, 9)
                    Spacer()
                    Text(Fmt.hm(Double(sec))).font(WFont.number(15, weight: .bold)).foregroundColor(.white)
                }
                HatchedBar(fraction: frac, color: Theme.stageColor(stage), usual: usual)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One statistic: today's value against the 30 days before, and the last 7 days.
struct MetricTrendCard: View {
    @EnvironmentObject var app: AppState
    var metric: DashboardMetric
    var date: String
    @State private var showInfo = false

    var body: some View {
        let keys = (0..<7).reversed().map { DayKey.adding(-$0, to: date) }
        let values: [Double?] = keys.map { k in app.day(k).flatMap { metric.value(day: $0, state: app) } }
        let today = values.last ?? nil
        let avg = app.baseline(metric, before: date)
        let usual = app.usualRange30(before: date) { metric.value(day: $0, state: app) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(metric.title).wLabel(11.5).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                Spacer(minLength: 10)
                InfoButton { showInfo = true }.offset(x: 6, y: -6)
            }
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.format(today)).font(WFont.number(24.5, weight: .bold)).foregroundColor(.white)
                    if today != nil && !metric.unit.isEmpty {
                        Text(metric.unit).font(WFont.text(11.5, weight: .medium)).foregroundColor(Theme.textSecondary)
                    }
                }
                if let today, let avg, abs(today - avg) > max(0.01, abs(avg) * 0.01) {
                    TrendArrow(up: today > avg, good: metric.higherIsBetter.map { (today > avg) == $0 }, size: 9).padding(.top, 5)
                }
            }
            .padding(.top, 6)
            Text(avg.map { metric.format($0) } ?? "—").font(WFont.number(11.5, weight: .bold)).foregroundColor(Color(hex: 0xBEC0C3))
                .padding(.top, 1)
            TrendChart(keys: keys, values: values, color: metric.color, format: { metric.format($0) }, average: avg, usual: usual)
                .padding(.top, 12)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
        .sheet(isPresented: $showInfo) { InfoSheet(title: metric.title, text: metric.explanation) }
    }
}

// MARK: - Récupération

struct RecoveryDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String
    @State private var editing = false

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: Fmt.dayTitle(date), spacing: 0) {
            BigScoreRing(progress: (d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery),
                         value: d.recovery.map { "\(Int($0.rounded()))" } ?? "—", suffix: d.recovery == nil ? "" : "%",
                         caption: "Récupération")
                .frame(height: 262)
            Text(zoneText(d)).font(WFont.text(14.5, weight: .medium)).foregroundColor(Color(hex: 0xC9CBCE))
                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            breakdown(d).padding(.top, 18)
            SectionTitle(title: "Récupération des\nderniers jours", onEdit: { editing = true })
                .padding(.top, 26)
            VStack(spacing: 14) {
                ForEach(app.settings.recoveryStats) { MetricTrendCard(metric: $0, date: date) }
            }
            .padding(.top, 18)
            Text("La récupération compare ta VFC, ta fréquence cardiaque au repos, ta respiration et ton sommeil de la nuit à tes propres moyennes. Elle s'affine après quelques nuits.")
                .font(WFont.text(11.5)).foregroundColor(Theme.textMuted).padding(.top, 16).padding(.horizontal, 4)
        }
        .sheet(isPresented: $editing) {
            MetricListEditor(title: "Récupération des derniers jours", choices: DashboardMetric.recoveryChoices,
                             selection: app.settings.recoveryStats) { app.settings.recoveryStats = $0 }
        }
    }

    private func breakdown(_ d: DayMetrics) -> some View {
        let hrvBase = app.average30(before: date) { $0.hrv }
        let rhrBase = app.average30(before: date) { $0.rhr }
        let respBase = app.average30(before: date) { $0.respRate }
        return PointerCard {
            BreakdownRow(icon: "waveform.path.ecg", title: "Variabilité de la fréquence cardiaque",
                         value: Fmt.int(d.hrv), unit: "ms",
                         state: ratioState(d.hrv, hrvBase, higher: true), valueWidth: 56)
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "heart", title: "Fréquence cardiaque au repos",
                         value: Fmt.int(d.rhr), unit: "bpm",
                         state: ratioState(d.rhr, rhrBase, higher: false), valueWidth: 56)
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "lungs", title: "Fréquence respiratoire",
                         value: Fmt.dec1(d.respRate), unit: "rpm",
                         state: respState(d.respRate, respBase), valueWidth: 56)
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "moon", title: "Performance du sommeil", value: Fmt.pct(d.sleepPerformance),
                         state: .higher(d.sleepPerformance, sufficient: 70, optimal: 85), valueWidth: 56)
            QualityLegend().padding(.top, 8)
        }
    }

    private func ratioState(_ v: Double?, _ base: Double?, higher: Bool) -> QualityState? {
        guard let v, let base, base > 0 else { return nil }
        let r = higher ? v / base : base / v
        if r >= 0.97 { return .optimal }
        if r >= 0.88 { return .sufficient }
        return .insufficient
    }

    private func respState(_ v: Double?, _ base: Double?) -> QualityState? {
        guard let v, let base else { return nil }
        let dev = abs(v - base)
        if dev <= 0.6 { return .optimal }
        if dev <= 1.2 { return .sufficient }
        return .insufficient
    }

    private func zoneText(_ d: DayMetrics) -> String {
        guard let r = d.recovery else {
            if let n = d.calibrationNights { return "Calibrage en cours (\(n)/\(Recovery.calibrationNights) nuits). Continue de porter ton bracelet la nuit." }
            return "Pas encore de récupération pour ce jour."
        }
        switch Recovery.zone(r) {
        case .green: return "Ton corps est prêt à encaisser un effort important aujourd'hui."
        case .yellow: return "Ton corps se maintient : un effort modéré est adapté."
        case .red: return "Ton corps a besoin de repos : privilégie la récupération."
        }
    }
}

// MARK: - Effort

struct StrainDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String
    @State private var points: [HRPoint] = []
    @State private var editing = false

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        let target = StrainTarget.forRecovery(d.recovery)
        DetailScaffold(title: Fmt.dayTitle(date), spacing: 0) {
            BigScoreRing(progress: (d.strain ?? 0) / 21, color: Theme.strain,
                         value: d.strain.map { Fmt.dec1($0) } ?? "—", caption: "Effort",
                         band: target.map { ($0.lowerBound / 21)...($0.upperBound / 21) },
                         marker: StrainTarget.optimal(for: d.recovery).map { $0 / 21 })
                .frame(height: 262)
            if let target {
                (Text("Effort optimal aujourd'hui : ").foregroundColor(Color(hex: 0xC9CBCE))
                 + Text("\(Fmt.dec1(target.lowerBound)) – \(Fmt.dec1(target.upperBound))").foregroundColor(.white))
                    .font(WFont.text(14.5, weight: .medium)).padding(.top, 4)
            }
            breakdown(d, target).padding(.top, 18)

            CardBox(title: "Effort de la journée") {
                if let start = d.cycleStart {
                    let end = min(d.cycleEnd ?? Int(Date().timeIntervalSince1970), Int(Date().timeIntervalSince1970))
                    if points.isEmpty {
                        ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 170)
                    } else {
                        DayHRChart(points: points, start: start, end: end, activities: d.activities,
                                   sleeps: [d.sleep].compactMap { $0 } + d.naps)
                    }
                } else {
                    Text("Pas encore de données pour ce jour.").font(WFont.text(14)).foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.top, 14)

            if !d.activities.isEmpty {
                VStack(spacing: 12) {
                    SectionLabel(text: "Activités")
                    ForEach(d.activities) { a in
                        NavigationLink(value: HomeRoute.activity(a.id)) {
                            ActivityRow(icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.name(a),
                                        start: Fmt.clock(a.start), end: Fmt.clock(a.end), color: Theme.strainBadge)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
                .padding(.top, 14)
            }

            CardBox(title: "Zones de fréquence cardiaque") { ZoneBars(seconds: d.zoneSeconds) }
                .padding(.top, 14)

            SectionTitle(title: "Effort des\nderniers jours", onEdit: { editing = true })
                .padding(.top, 26)
            VStack(spacing: 14) {
                ForEach(app.settings.strainStats) { MetricTrendCard(metric: $0, date: date) }
            }
            .padding(.top, 18)
            Text("L'effort mesure ta charge cardiovasculaire de 0 à 21 (échelle logarithmique), à partir du temps passé au-dessus de ton niveau de repos éveillé.")
                .font(WFont.text(11.5)).foregroundColor(Theme.textMuted).padding(.top, 16).padding(.horizontal, 4)
        }
        .task(id: "\(d.cycleStart ?? 0)-\(app.dataVersion)") {
            guard let start = d.cycleStart else { return }
            let end = min(d.cycleEnd ?? Int(Date().timeIntervalSince1970), Int(Date().timeIntervalSince1970))
            points = await app.minuteHR(from: start, to: end)
        }
        .sheet(isPresented: $editing) {
            MetricListEditor(title: "Effort des derniers jours", choices: DashboardMetric.strainChoices,
                             selection: app.settings.strainStats) { app.settings.strainStats = $0 }
        }
    }

    private func breakdown(_ d: DayMetrics, _ target: ClosedRange<Double>?) -> some View {
        let calBase = app.average30(before: date) { $0.calories }
        let hrBase = app.average30(before: date) { $0.avgHR }
        let stepsBase = app.average30(before: date) { $0.steps.map(Double.init) }
        func trend(_ v: Double?, _ b: Double?) -> (up: Bool, good: Bool?)? {
            guard let v, let b, abs(v - b) > abs(b) * 0.02 else { return nil }
            return (v > b, nil)
        }
        var state: QualityState?
        if let s = d.strain, let t = target {
            state = t.contains(s) ? .optimal : (s < t.lowerBound ? .sufficient : .insufficient)
        }
        return PointerCard {
            BreakdownRow(icon: "scope", title: "Effort optimal",
                         value: target.map { "\(Fmt.dec1($0.lowerBound))–\(Fmt.dec1($0.upperBound))" } ?? "—", state: state,
                         valueWidth: 80)
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "flame", title: "Calories", value: Fmt.int(d.calories), unit: "kcal", state: nil, trend: trend(d.calories, calBase))
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "heart", title: "FC moyenne", value: Fmt.int(d.avgHR), unit: "bpm", state: nil,
                         trend: trend(d.avgHR, hrBase))
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "bolt.heart", title: "FC max", value: d.maxHR.map { "\($0)" } ?? "—", unit: "bpm", state: nil, trend: nil)
            Rectangle().fill(Theme.separator).frame(height: 1)
            BreakdownRow(icon: "shoeprints.fill", title: "Pas", value: Fmt.int(d.steps.map(Double.init)), state: nil,
                         trend: trend(d.steps.map(Double.init), stepsBase))
        }
    }
}

// MARK: - "MODIFIER": choose and order the statistics of a screen

struct MetricListEditor: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var choices: [DashboardMetric]
    @State var selection: [DashboardMetric]
    var onSave: ([DashboardMetric]) -> Void

    init(title: String, choices: [DashboardMetric], selection: [DashboardMetric], onSave: @escaping ([DashboardMetric]) -> Void) {
        self.title = title
        self.choices = choices
        self._selection = State(initialValue: selection)
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: title) { dismiss() }
                List {
                    ForEach(selection) { m in
                        row(m, trailing: AnyView(
                            Button { withAnimation { selection.removeAll { $0 == m } } } label: {
                                Image(systemName: "minus").font(.system(size: 20, weight: .light)).foregroundColor(.white).frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                        ))
                    }
                    .onMove { selection.move(fromOffsets: $0, toOffset: $1) }

                    HStack(spacing: 12) {
                        Text("Ajouter").wLabel(11.4, color: Color(hex: 0x8C8F92))
                        Rectangle().fill(Color(hex: 0x2C2F34)).frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 26, leading: 16, bottom: 8, trailing: 16))
                    .moveDisabled(true)

                    ForEach(choices.filter { !selection.contains($0) }) { m in
                        row(m, trailing: AnyView(
                            Button { withAnimation { selection.append(m) } } label: {
                                Image(systemName: "plus").font(.system(size: 20, weight: .light)).foregroundColor(.white).frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                        ))
                        .moveDisabled(true)
                    }
                    Color.clear.frame(height: 100).listRowBackground(Color.clear).listRowSeparator(.hidden).moveDisabled(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            LinearGradient(stops: [.init(color: Theme.bgBottom.opacity(0), location: 0),
                                   .init(color: Theme.bgBottom.opacity(0.95), location: 0.55),
                                   .init(color: Theme.bgBottom, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            OutlineButton(title: "Enregistrer") {
                onSave(selection)
                dismiss()
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ m: DashboardMetric, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.icon).font(.system(size: 17, weight: .light)).foregroundColor(Color(hex: 0x9A9EA2)).frame(width: 22)
            Text(m.title).wLabel(12).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            trailing
        }
        .frame(minHeight: 46)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardGradient)
                .padding(.vertical, 5).padding(.horizontal, 16)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 22))
    }
}
