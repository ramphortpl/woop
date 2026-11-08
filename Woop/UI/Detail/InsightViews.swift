import SwiftUI

extension View {
    /// Registers every pushable destination, so any tab's stack can open them.
    func withAppRoutes() -> some View {
        navigationDestination(for: HomeRoute.self) { route in
            RouteDestination(route: route)
        }
    }
}

struct RouteDestination: View {
    @EnvironmentObject var app: AppState
    var route: HomeRoute

    var body: some View {
        switch route {
        case .sleep: SleepDetailView(date: app.selectedDate)
        case .recovery: RecoveryDetailView(date: app.selectedDate)
        case .strain: StrainDetailView(date: app.selectedDate)
        case .activities: ActivitiesListView(date: app.selectedDate)
        case .activity(let id): ActivityDetailView(date: app.selectedDate, activityID: id)
        case .metric(let m): MetricDetailView(metric: m, date: app.selectedDate)
        case .device: DeviceView()
        case .outlook: DailyOutlookView(date: app.selectedDate)
        }
    }
}

/// One dashboard metric over time.
struct MetricDetailView: View {
    @EnvironmentObject var app: AppState
    var metric: DashboardMetric
    var date: String
    @State private var range = 7

    var body: some View {
        let keys = (0..<range).reversed().map { DayKey.adding(-$0, to: date) }
        let values: [Double?] = keys.map { k in app.day(k).flatMap { metric.value(day: $0, state: app) } }
        let present = values.compactMap { $0 }
        let today = app.day(date).flatMap { metric.value(day: $0, state: app) }
        let avg = app.baseline(metric, before: date)
        DetailScaffold(title: metric.title, subtitle: Fmt.longDate(date)) {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.format(today)).font(WFont.number(58, weight: .bold)).foregroundColor(.white)
                        if today != nil && !metric.unit.isEmpty {
                            Text(metric.unit).font(WFont.text(15, weight: .medium)).foregroundColor(Theme.textSecondary)
                        }
                    }
                    if let today, let avg, abs(today - avg) > max(0.01, abs(avg) * 0.01) {
                        TrendArrow(up: today > avg, good: metric.higherIsBetter.map { (today > avg) == $0 }, size: 12).padding(.top, 12)
                    }
                }
                Text("Moyenne sur 30 jours : \(metric.format(avg))\(avg == nil || metric.unit.isEmpty ? "" : " " + metric.unit)")
                    .font(WFont.text(13, weight: .medium)).foregroundColor(Theme.textSecondary)
            }
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach([7, 30, 90], id: \.self) { r in
                    Button {
                        Haptics.select()
                        withAnimation(.easeInOut(duration: 0.2)) { range = r }
                    } label: {
                        Text("\(r) J").wLabel(11, color: range == r ? .black : .white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Capsule().fill(range == r ? Color.white : Theme.pill.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Theme.pillOuter))

            CardBox(title: "Tendance") {
                if present.count >= 2 {
                    TrendChart(keys: keys, values: values, color: metric.color, format: { metric.format($0) },
                               average: avg, usual: app.usualRange30(before: date) { metric.value(day: $0, state: app) },
                               height: 170)
                } else {
                    Text("Pas encore assez de données.").font(WFont.text(14)).foregroundColor(Theme.textSecondary)
                }
            }
            TileGrid(tiles: [
                StatTile(title: "Moyenne", value: metric.format(Stats.mean(present)), unit: present.isEmpty ? "" : metric.unit),
                StatTile(title: "Minimum", value: metric.format(present.min()), unit: present.isEmpty ? "" : metric.unit),
                StatTile(title: "Maximum", value: metric.format(present.max()), unit: present.isEmpty ? "" : metric.unit),
                StatTile(title: "Jours mesurés", value: "\(present.count)"),
            ])
            Text(metric.explanation).font(WFont.text(12.5)).foregroundColor(Theme.textTertiary).lineSpacing(2)
        }
    }
}

// MARK: - Daily outlook

struct DailyOutlookView: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: "Perspectives quotidiennes", subtitle: Fmt.longDate(date)) {
            CardBox {
                Text(Coach.greeting(app.settings.profile.firstName)).font(WFont.title(24)).foregroundColor(.white)
                Text(Coach.outlook(day: d, app: app)).font(WFont.text(16)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let target = StrainTarget.forRecovery(d.recovery) {
                CardBox(title: "Effort optimal") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Fmt.dec1(target.lowerBound)) – \(Fmt.dec1(target.upperBound))")
                            .font(WFont.number(40, weight: .bold)).foregroundColor(Theme.strain)
                        Spacer()
                        Text("actuel : \(Fmt.dec1(d.strain))").font(WFont.number(18)).foregroundColor(Theme.textSecondary)
                    }
                    Text("Une plage indicative selon ta récupération, pas une consigne.").font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                }
            }
            CardBox(title: "Ce soir") {
                Text(Coach.tonight(app: app)).font(WFont.text(15)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Coach

/// Deterministic, on-device coach: plain-language readings of the wearer's own numbers.
enum Coach {
    static func greeting(_ name: String) -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 5 ? "Bonne nuit" : (h < 18 ? "Bonjour" : "Bonsoir")
        return name.isEmpty ? base : "\(base) \(name)"
    }

    @MainActor
    static func outlook(day d: DayMetrics, app: AppState) -> String {
        var parts: [String] = []
        if let r = d.recovery {
            switch Recovery.zone(r) {
            case .green: parts.append("Ta récupération est de \(Int(r)) % : tu es prêt pour une journée exigeante.")
            case .yellow: parts.append("Ta récupération est de \(Int(r)) % : ton corps se maintient, un effort modéré est idéal.")
            case .red: parts.append("Ta récupération est de \(Int(r)) % : ton corps est sous tension, accorde-toi une journée plus légère.")
            }
        } else if let n = d.calibrationNights {
            parts.append("Ta récupération est en calibrage (\(n)/\(Recovery.calibrationNights) nuits).")
        }
        if let s = d.sleep {
            var t = "Tu as dormi \(Fmt.hmLong(Double(s.asleepSec)))"
            if let p = d.sleepPerformance { t += ", soit \(Int(p)) % de ton besoin" }
            parts.append(t + ".")
        }
        let hist = app.history(upTo: DayKey.adding(-1, to: d.date), count: 30)
        if let hrv = d.hrv, let base = Stats.mean(hist.compactMap(\.hrv)) {
            let delta = Int(((hrv - base) / base * 100).rounded())
            if abs(delta) >= 5 {
                parts.append("Ta VFC (\(Int(hrv)) ms) est \(delta > 0 ? "supérieure" : "inférieure") de \(abs(delta)) % à ta moyenne.")
            } else {
                parts.append("Ta VFC (\(Int(hrv)) ms) est proche de ta moyenne.")
            }
        }
        if let rhr = d.rhr, let base = Stats.mean(hist.compactMap(\.rhr)), rhr - base >= 3 {
            parts.append("Ta fréquence cardiaque au repos est plus élevée que d'habitude (+\(Int(rhr - base)) bpm) : surveille la fatigue, le stress ou un début de maladie.")
        }
        if parts.isEmpty { return "Porte ton bracelet et synchronise-le pour obtenir tes perspectives du jour." }
        return parts.joined(separator: " ")
    }

    @MainActor
    static func tonight(app: AppState) -> String {
        guard let bed = app.recommendedBedtime, let need = app.day(app.today)?.tonightNeedSec else {
            return "Ton besoin de sommeil apparaîtra après ta première nuit enregistrée."
        }
        var t = "Couche-toi vers \(Fmt.clock24(bed)) pour dormir \(Fmt.hmLong(need))."
        if let debt = app.day(app.today)?.sleepDebtSec, debt > 20 * 60 {
            t += " Ce besoin inclut \(Fmt.hmLong(debt)) de dette de sommeil."
        }
        return t
    }

    struct QA: Identifiable { let id = UUID(); let q: String; let a: String }

    @MainActor
    static func answer(_ q: String, app: AppState) -> String {
        let d = app.day(app.today) ?? app.selected
        let hist = app.history(upTo: app.today, count: 30)
        switch q {
        case questions[0]: return outlook(day: d, app: app)
        case questions[1]:
            guard let target = StrainTarget.forRecovery(d.recovery) else { return "Il me faut ta récupération du jour pour te répondre." }
            return "Avec \(Int(d.recovery ?? 0)) % de récupération, une journée entre \(Fmt.dec1(target.lowerBound)) et \(Fmt.dec1(target.upperBound)) d'effort est cohérente. Tu en es à \(Fmt.dec1(d.strain))."
        case questions[2]:
            let sleeps = hist.compactMap(\.sleep)
            guard !sleeps.isEmpty else { return "Je n'ai pas encore de nuits enregistrées." }
            let avg = Stats.mean(sleeps.map { Double($0.asleepSec) }) ?? 0
            let cons = Stats.mean(hist.compactMap(\.sleepConsistency))
            var t = "Sur 30 jours, tu dors en moyenne \(Fmt.hmLong(avg))."
            if let c = cons { t += " Ta régularité est de \(Int(c)) % ; des heures de coucher et de lever stables améliorent la qualité du sommeil." }
            if let eff = Stats.mean(sleeps.map(\.efficiency)), eff < 0.85 { t += " Ton efficacité (\(Int(eff * 100)) %) est un peu basse : évite les écrans et la caféine le soir." }
            return t
        case questions[3]:
            let week = hist.suffix(7)
            let strain = Stats.mean(week.compactMap(\.strain))
            let rec = Stats.mean(week.compactMap(\.recovery))
            return "Cette semaine : effort moyen \(Fmt.dec1(strain)), récupération moyenne \(rec.map { "\(Int($0)) %" } ?? "—"), \(week.flatMap(\.activities).count) activité(s)."
        default:
            return tonight(app: app)
        }
    }

    static let questions = [
        "Comment je me sens aujourd'hui ?",
        "Quel effort viser aujourd'hui ?",
        "Comment améliorer mon sommeil ?",
        "Résumé de ma semaine",
        "À quelle heure me coucher ?",
    ]
}

struct CoachView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var thread: [Coach.QA] = []

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: "Coach") { dismiss() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pose une question : les réponses sont calculées sur ton iPhone à partir de tes propres données, sans compte ni cloud.")
                            .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                        ForEach(thread) { qa in
                            Text(qa.q).font(WFont.text(15, weight: .semibold)).foregroundColor(.black)
                                .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(qa.a).font(WFont.text(15)).foregroundColor(.white)
                                .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardInner))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                VStack(spacing: 8) {
                    ForEach(Coach.questions, id: \.self) { q in
                        Button {
                            withAnimation { thread.append(Coach.QA(q: q, a: Coach.answer(q, app: app))) }
                        } label: {
                            Text(q).font(WFont.text(14, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(Capsule().stroke(Theme.coachPurple.opacity(0.7), lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }
}
