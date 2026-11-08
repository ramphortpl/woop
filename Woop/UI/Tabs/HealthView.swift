import SwiftUI

/// "Santé" — health monitor: overnight vitals against the wearer's own normal range.
struct HealthView: View {
    @EnvironmentObject var app: AppState

    struct Vital: Identifiable {
        let id: String
        let title: String
        let icon: String
        let value: Double?
        let unit: String
        let range: ClosedRange<Double>?
        let format: (Double?) -> String
        let metric: DashboardMetric?
    }

    var body: some View {
        let d = app.day(app.selectedDate) ?? .empty(app.selectedDate)
        let hist = app.history(upTo: DayKey.adding(-1, to: app.selectedDate), count: 30)
        let vitals = [
            Vital(id: "rhr", title: "Fréquence cardiaque au repos", icon: "arrow.down.heart", value: d.rhr, unit: "bpm",
                  range: range(hist.compactMap(\.rhr), floor: 2), format: Fmt.int, metric: .rhr),
            Vital(id: "hrv", title: "Variabilité de la fréquence cardiaque", icon: "waveform.path.ecg", value: d.hrv, unit: "ms",
                  range: range(hist.compactMap(\.hrv), floor: 4), format: Fmt.int, metric: .hrv),
            Vital(id: "resp", title: "Fréquence respiratoire", icon: "lungs", value: d.respRate, unit: "rpm",
                  range: range(hist.compactMap(\.respRate), floor: 0.6), format: Fmt.dec1, metric: .respRate),
            Vital(id: "spo2", title: "Oxygène sanguin (estimation)", icon: "drop", value: d.spo2, unit: "%",
                  range: range(hist.compactMap(\.spo2), floor: 1), format: Fmt.dec1, metric: nil),
            Vital(id: "temp", title: "Température cutanée", icon: "thermometer.medium", value: d.skinTemp, unit: "°C",
                  range: range(hist.compactMap(\.skinTemp), floor: 0.4), format: Fmt.dec1, metric: nil),
        ]
        let inRange = vitals.filter { v in v.value != nil && v.range != nil && v.range!.contains(v.value!) }.count
        let measured = vitals.filter { $0.value != nil && $0.range != nil }.count

        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Santé").font(WFont.title(32)).foregroundColor(.white)
                        Spacer()
                        Text(Fmt.dayTitle(app.selectedDate)).wLabel(12, color: Theme.textSecondary)
                    }
                    .padding(.top, 12)
                    CardBox(title: "Moniteur de santé") {
                        HStack(alignment: .firstTextBaseline) {
                            Text(measured > 0 ? "\(inRange)/\(measured)" : "—").font(WFont.number(44, weight: .bold)).foregroundColor(.white)
                            Text("paramètres dans ta norme").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textSecondary)
                        }
                        Text("Mesurés pendant ton sommeil et comparés à tes 30 derniers jours.").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                    }
                    ForEach(vitals) { v in
                        if let m = v.metric {
                            NavigationLink(value: HomeRoute.metric(m)) { vitalRow(v) }.buttonStyle(.plain)
                        } else {
                            vitalRow(v)
                        }
                    }
                    CardBox(title: "Sommeil moyen — 30 jours") {
                        let sleeps = hist.compactMap(\.sleep)
                        if sleeps.isEmpty {
                            Text("Pas encore de nuits enregistrées.").foregroundColor(Theme.textSecondary)
                        } else {
                            let total = Double(sleeps.reduce(0) { $0 + $1.inBedSec })
                            stageLine("Éveil", .wake, Double(sleeps.reduce(0) { $0 + $1.awakeSec }), total)
                            stageLine("Léger", .light, Double(sleeps.reduce(0) { $0 + $1.lightSec }), total)
                            stageLine("Profond (SWS)", .deep, Double(sleeps.reduce(0) { $0 + $1.deepSec }), total)
                            stageLine("Paradoxal (REM)", .rem, Double(sleeps.reduce(0) { $0 + $1.remSec }), total)
                        }
                    }
                    Text("Woop n'est pas un dispositif médical. Ces mesures sont des estimations et ne remplacent pas l'avis d'un professionnel de santé.")
                        .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withAppRoutes()
    }

    private func range(_ v: [Double], floor: Double) -> ClosedRange<Double>? {
        guard v.count >= 4, let m = Stats.mean(v), let sd = Stats.std(v) else { return nil }
        let w = max(1.5 * sd, floor)
        return (m - w)...(m + w)
    }

    private func vitalRow(_ v: Vital) -> some View {
        let ok: Bool? = (v.value != nil && v.range != nil) ? v.range!.contains(v.value!) : nil
        return HStack(spacing: 14) {
            Image(systemName: v.icon).font(.system(size: 20)).foregroundColor(Theme.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(v.title).wLabel(11.5, tracking: 1.2).lineLimit(2).minimumScaleFactor(0.8)
                if let r = v.range {
                    Text("Norme : \(v.format(r.lowerBound)) – \(v.format(r.upperBound)) \(v.unit)").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                } else {
                    Text("Norme en cours d'apprentissage").font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(ok ? Theme.recoveryGreen : Theme.recoveryYellow)
            }
            Text(v.format(v.value)).font(WFont.number(24, weight: .bold)).foregroundColor(.white)
            Text(v.value == nil ? "" : v.unit).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
    }

    private func stageLine(_ name: String, _ s: SleepStage, _ sec: Double, _ total: Double) -> some View {
        HStack {
            Circle().fill(Theme.stageColor(s)).frame(width: 10, height: 10)
            Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text(total > 0 ? "\(Int((sec / total * 100).rounded())) %" : "—").font(WFont.number(18, weight: .bold)).foregroundColor(.white)
        }
    }
}

/// "Communauté" — offline: your streak, records and weekly recap (no account, no server).
struct CommunityView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let all = app.history(upTo: app.today, count: 400)
        let week = all.suffix(7)
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Communauté").font(WFont.title(32)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.top, 12)
                    CardBox {
                        HStack(spacing: 16) {
                            Image(systemName: "flame.fill").font(.system(size: 40))
                                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(app.streak) jour\(app.streak > 1 ? "s" : "")").font(WFont.number(34, weight: .bold)).foregroundColor(.white)
                                Text("Série de jours portés").wLabel(11, color: Theme.textSecondary)
                            }
                        }
                    }
                    CardBox(title: "Ta semaine") {
                        HStack(spacing: 12) {
                            StatTile(title: "Récup. moy.", value: Fmt.pct(Stats.mean(week.compactMap(\.recovery))), color: Theme.recoveryColor(Stats.mean(week.compactMap(\.recovery))))
                            StatTile(title: "Effort moy.", value: Fmt.dec1(Stats.mean(week.compactMap(\.strain))), color: Theme.strain)
                        }
                        HStack(spacing: 12) {
                            StatTile(title: "Sommeil moy.", value: Fmt.hm(Stats.mean(week.compactMap { $0.sleep.map { Double($0.asleepSec) } })), color: Theme.sleep)
                            StatTile(title: "Activités", value: "\(week.flatMap(\.activities).count)")
                        }
                    }
                    CardBox(title: "Tes records") {
                        record("Meilleure récupération", all.compactMap(\.recovery).max().map { Fmt.pct($0) })
                        record("Effort le plus élevé", all.compactMap(\.strain).max().map { Fmt.dec1($0) })
                        record("Plus longue nuit", all.compactMap { $0.sleep?.asleepSec }.max().map { Fmt.hm(Double($0)) })
                        record("VFC la plus haute", all.compactMap(\.hrv).max().map { "\(Fmt.int($0)) ms" })
                        record("FC au repos la plus basse", all.compactMap(\.rhr).min().map { "\(Fmt.int($0)) bpm" })
                        record("Le plus de pas", all.compactMap(\.steps).max().map { Fmt.int(Double($0)) })
                    }
                    CardBox(title: "Défis personnels") {
                        challenge("7 nuits de plus de 7 h", count: week.filter { ($0.sleep?.asleepSec ?? 0) >= 7 * 3600 }.count, goal: 7)
                        challenge("5 jours avec un effort ≥ 10", count: week.filter { ($0.strain ?? 0) >= 10 }.count, goal: 5)
                        challenge("Régularité ≥ 80 % sur 7 jours", count: week.filter { ($0.sleepConsistency ?? 0) >= 80 }.count, goal: 7)
                    }
                    Text("Les équipes et classements WHOOP nécessitent un compte en ligne : Woop fonctionne entièrement hors ligne, tes données restent sur ton iPhone.")
                        .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withAppRoutes()
    }

    private func record(_ t: String, _ v: String?) -> some View {
        HStack {
            Text(t).font(.system(size: 14)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(v ?? "—").font(WFont.number(19, weight: .bold)).foregroundColor(.white)
        }
    }

    private func challenge(_ t: String, count: Int, goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("\(min(count, goal))/\(goal)").font(WFont.number(15, weight: .bold)).foregroundColor(count >= goal ? Theme.recoveryGreen : Theme.textSecondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(count >= goal ? Theme.recoveryGreen : Theme.strain)
                        .frame(width: g.size.width * CGFloat(min(count, goal)) / CGFloat(goal))
                }
            }
            .frame(height: 6)
        }
    }
}
