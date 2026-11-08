import SwiftUI

/// Header for pushed screens: back chevron, uppercase title, date.
struct DetailHeader: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String?

    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(title).wLabel(15, tracking: 2.2)
                if let subtitle { Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textSecondary) }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 8)
    }
}

/// Generic scrolling detail scaffold.
struct DetailScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                DetailHeader(title: title, subtitle: subtitle)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16, content: content)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct CardBox<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).wLabel(12.5, color: Theme.textSecondary) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
    }
}

/// Pills grid helper.
struct TileGrid: View {
    var tiles: [StatTile]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in t }
        }
    }
}

// MARK: - Sleep

struct SleepDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: "Sommeil", subtitle: Fmt.longDate(date)) {
            ScoreRing(progress: (d.sleepPerformance ?? 0) / 100, color: Theme.sleep, lineWidth: 14, size: 190,
                      valueText: d.sleepPerformance.map { "\(Int($0.rounded()))" } ?? "—", suffix: d.sleepPerformance == nil ? "" : "%", valueSize: 64)
                .padding(.top, 8)
            Text("Performance du sommeil").wLabel(12, color: Theme.textSecondary)

            if let s = d.sleep {
                HStack(spacing: 12) {
                    StatTile(title: "Heures de sommeil", value: Fmt.hm(Double(s.asleepSec)))
                    StatTile(title: "Sommeil nécessaire", value: Fmt.hm(d.sleepNeedSec))
                }
                CardBox(title: "Phases de sommeil") {
                    HStack {
                        Text(Fmt.clock(s.start)).font(WFont.number(15)).foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text(Fmt.clock(s.end)).font(WFont.number(15)).foregroundColor(Theme.textSecondary)
                    }
                    Hypnogram(stages: s.stages).frame(height: 120)
                    VStack(spacing: 10) {
                        stageRow(.wake, "Éveil", s.awakeSec, s.inBedSec)
                        stageRow(.light, "Léger", s.lightSec, s.inBedSec)
                        stageRow(.deep, "Profond (SWS)", s.deepSec, s.inBedSec)
                        stageRow(.rem, "Paradoxal (REM)", s.remSec, s.inBedSec)
                    }
                }
                TileGrid(tiles: [
                    StatTile(title: "Temps passé au lit", value: Fmt.hm(Double(s.inBedSec))),
                    StatTile(title: "Efficacité du sommeil", value: Fmt.pct(s.efficiency * 100)),
                    StatTile(title: "Régularité du sommeil", value: Fmt.pct(d.sleepConsistency)),
                    StatTile(title: "Sommeil réparateur", value: Fmt.hm(Double(s.restorativeSec)), caption: Fmt.pct(s.restorativeFraction * 100) + " du sommeil"),
                    StatTile(title: "Latence d'endormissement", value: "\(s.latencySec / 60)", unit: "min"),
                    StatTile(title: "Perturbations", value: "\(s.disturbances)"),
                    StatTile(title: "Cycles de sommeil", value: "\(s.cycles)"),
                    StatTile(title: "Fréquence respiratoire", value: Fmt.dec1(s.respRate), unit: "rpm"),
                    StatTile(title: "Dette de sommeil", value: Fmt.hm(d.sleepDebtSec)),
                    StatTile(title: "FC moyenne (sommeil)", value: Fmt.int(s.avgHR), unit: "bpm"),
                ])
                if !d.naps.isEmpty {
                    CardBox(title: "Siestes") {
                        ForEach(d.naps) { n in
                            HStack {
                                Text("\(Fmt.clock(n.start)) – \(Fmt.clock(n.end))").font(WFont.number(17)).foregroundColor(.white)
                                Spacer()
                                Text(Fmt.hm(Double(n.asleepSec))).font(WFont.number(17, weight: .bold)).foregroundColor(Theme.sleep)
                            }
                        }
                    }
                }
                if !s.bandDetected {
                    Text("Nuit détectée à partir des mouvements et de la fréquence cardiaque (l'état de sommeil du bracelet n'était pas disponible).")
                        .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                }
            } else {
                CardBox {
                    Text("Aucun sommeil détecté pour cette journée. Porte ton bracelet la nuit et synchronise-le le matin.")
                        .font(.system(size: 15)).foregroundColor(Theme.textSecondary)
                }
            }
            weekBars
            Text("Les phases de sommeil sont estimées à partir de la fréquence cardiaque, de sa variabilité, de la respiration et des mouvements. Ce n'est pas une polysomnographie.")
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
        }
    }

    private func stageRow(_ stage: SleepStage, _ name: String, _ sec: Int, _ total: Int) -> some View {
        HStack {
            Circle().fill(Theme.stageColor(stage)).frame(width: 10, height: 10)
            Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text(total > 0 ? "\(Int((Double(sec) / Double(total) * 100).rounded())) %" : "—")
                .font(WFont.number(15)).foregroundColor(Theme.textSecondary)
            Text(Fmt.hm(Double(sec))).font(WFont.number(17, weight: .bold)).foregroundColor(.white).frame(width: 54, alignment: .trailing)
        }
    }

    private var weekBars: some View {
        let keys = (0..<7).reversed().map { DayKey.adding(-$0, to: date) }
        let vals = keys.map { k in app.day(k)?.sleep.map { Double($0.asleepSec) / 3600 } }
        return CardBox(title: "Heures de sommeil — 7 jours") {
            MiniBars(values: vals, labels: keys.map(Fmt.shortWeekday), color: { _ in Theme.sleep },
                     maxValue: max(9, vals.compactMap { $0 }.max() ?? 9), format: { Fmt.hm($0 * 3600) })
        }
    }
}

// MARK: - Recovery

struct RecoveryDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        let hist = app.history(upTo: DayKey.adding(-1, to: date), count: 30)
        DetailScaffold(title: "Récupération", subtitle: Fmt.longDate(date)) {
            ScoreRing(progress: (d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery), lineWidth: 14, size: 190,
                      valueText: d.recovery.map { "\(Int($0.rounded()))" } ?? "—", suffix: d.recovery == nil ? "" : "%", valueSize: 64)
                .padding(.top, 8)
            Text(zoneText(d)).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 8)

            CardBox(title: "Facteurs de récupération") {
                contributor("Variabilité de la fréquence cardiaque", d.hrv, "ms", Stats.mean(hist.compactMap(\.hrv)), higherBetter: true, fmt: Fmt.int)
                Divider().overlay(Theme.separator)
                contributor("Fréquence cardiaque au repos", d.rhr, "bpm", Stats.mean(hist.compactMap(\.rhr)), higherBetter: false, fmt: Fmt.int)
                Divider().overlay(Theme.separator)
                contributor("Fréquence respiratoire", d.respRate, "rpm", Stats.mean(hist.compactMap(\.respRate)), higherBetter: nil, fmt: Fmt.dec1)
                Divider().overlay(Theme.separator)
                contributor("Performance du sommeil", d.sleepPerformance, "%", Stats.mean(hist.compactMap(\.sleepPerformance)), higherBetter: true, fmt: Fmt.int)
                if d.spo2 != nil || d.skinTemp != nil {
                    Divider().overlay(Theme.separator)
                    contributor("Oxygène sanguin (estimation)", d.spo2, "%", Stats.mean(hist.compactMap(\.spo2)), higherBetter: nil, fmt: Fmt.dec1)
                    Divider().overlay(Theme.separator)
                    contributor("Température cutanée", d.skinTemp, "°C", Stats.mean(hist.compactMap(\.skinTemp)), higherBetter: nil, fmt: Fmt.dec1)
                }
            }

            let keys = (0..<7).reversed().map { DayKey.adding(-$0, to: date) }
            let vals = keys.map { app.day($0)?.recovery }
            CardBox(title: "Récupération — 7 jours") {
                MiniBars(values: vals, labels: keys.map(Fmt.shortWeekday), color: { Theme.recoveryColor($0) }, maxValue: 100,
                         format: { "\(Int($0.rounded()))%" })
            }
            let hrvKeys = (0..<30).reversed().map { DayKey.adding(-$0, to: date) }
            CardBox(title: "VFC — 30 jours (ms)") {
                LineTrace(values: hrvKeys.map { app.day($0)?.hrv }, color: Theme.recoveryGreen).frame(height: 90)
            }
            Text("La récupération compare ta VFC, ta fréquence cardiaque au repos, ta respiration et ton sommeil de la nuit à tes propres moyennes. Elle s'affine après quelques nuits.")
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
        }
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

    private func contributor(_ name: String, _ v: Double?, _ unit: String, _ base: Double?, higherBetter: Bool?, fmt: (Double?) -> String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).wLabel(11.5, tracking: 1.1).lineLimit(2).minimumScaleFactor(0.8)
                Text("Moy. 30 j : \(fmt(base)) \(base == nil ? "" : unit)").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
            }
            Spacer()
            if let v, let base, abs(v - base) > 0.0001 {
                let up = v > base
                let good: Bool? = higherBetter.map { up == $0 }
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 9))
                    .foregroundColor(good == nil ? Theme.textSecondary : (good! ? Theme.recoveryGreen : Theme.recoveryRed))
            }
            Text(fmt(v)).font(WFont.number(24, weight: .bold)).foregroundColor(.white)
            Text(v == nil ? "" : unit).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary)
        }
    }
}

// MARK: - Strain

struct StrainDetailView: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: "Effort", subtitle: Fmt.longDate(date)) {
            ScoreRing(progress: (d.strain ?? 0) / 21, color: Theme.strain, lineWidth: 14, size: 190,
                      valueText: d.strain.map { Fmt.dec1($0) } ?? "—", valueSize: 64)
                .padding(.top, 8)
            if let target = StrainTarget.forRecovery(d.recovery) {
                Text("Effort optimal aujourd'hui : \(Fmt.dec1(target.lowerBound)) – \(Fmt.dec1(target.upperBound))")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textSecondary)
            }
            if d.strainCurve.count > 1 {
                CardBox(title: "Effort au fil de la journée") {
                    LineTrace(values: d.strainCurve.map { Optional($0) }, color: Theme.strain, minY: 0, maxY: max(10, d.strainCurve.max() ?? 10))
                        .frame(height: 110)
                    HStack {
                        Text(Fmt.clock(d.cycleStart)).font(WFont.number(13)).foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text(Fmt.clock(d.cycleEnd)).font(WFont.number(13)).foregroundColor(Theme.textTertiary)
                    }
                }
            }
            TileGrid(tiles: [
                StatTile(title: "Calories", value: Fmt.int(d.calories), unit: "kcal", caption: d.activeCalories.map { "dont \(Fmt.int($0)) actives" }),
                StatTile(title: "Pas", value: Fmt.int(d.steps.map(Double.init))),
                StatTile(title: "FC moyenne", value: Fmt.int(d.avgHR), unit: "bpm"),
                StatTile(title: "FC max", value: Fmt.int(d.maxHR.map(Double.init)), unit: "bpm"),
            ])
            if !d.activities.isEmpty {
                CardBox(title: "Activités") {
                    ForEach(d.activities) { a in
                        NavigationLink(value: HomeRoute.activity(a.id)) {
                            HStack(spacing: 12) {
                                Image(systemName: Sport.icon(a.sport)).font(.system(size: 18)).foregroundColor(.white)
                                    .frame(width: 38, height: 38).background(Circle().fill(Theme.strainBadge))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Sport.label(a.sport)).wLabel(12.5)
                                    Text("\(Fmt.clock(a.start)) – \(Fmt.clock(a.end)) · \(Fmt.hmLong(Double(a.durationSec)))")
                                        .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                                }
                                Spacer()
                                Text(Fmt.dec1(a.strain)).font(WFont.number(22, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            CardBox(title: "Zones de fréquence cardiaque") { ZoneBars(seconds: d.zoneSeconds) }
            if d.hrTrace.contains(where: { $0 > 0 }) {
                CardBox(title: "Fréquence cardiaque") {
                    LineTrace(values: d.hrTrace.map { $0 > 0 ? Double($0) : nil }, color: Theme.recoveryRed).frame(height: 110)
                }
            }
            let keys = (0..<7).reversed().map { DayKey.adding(-$0, to: date) }
            CardBox(title: "Effort — 7 jours") {
                MiniBars(values: keys.map { app.day($0)?.strain }, labels: keys.map(Fmt.shortWeekday),
                         color: { _ in Theme.strain }, maxValue: 21)
            }
            Text("L'effort mesure ta charge cardiovasculaire de 0 à 21 (échelle logarithmique), à partir du temps passé au-dessus de ton niveau de repos éveillé.")
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
        }
    }
}

/// Recommended strain band from recovery (a range, never an instruction).
enum StrainTarget {
    static func forRecovery(_ r: Double?) -> ClosedRange<Double>? {
        guard let r else { return nil }
        switch r {
        case ..<34: return 4...9
        case ..<67: return 9...13.5
        default: return 13.5...18
        }
    }
}
