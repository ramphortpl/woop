import SwiftUI

struct ActivitiesListView: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        DetailScaffold(title: "Activités du jour", subtitle: Fmt.longDate(date)) {
            if let s = d.sleep {
                NavigationLink(value: HomeRoute.sleep) {
                    ActivityRow(icon: "moon.fill", value: Fmt.hm(Double(s.asleepSec)), title: "Sommeil",
                                start: Fmt.clock(s.start), end: Fmt.clock(s.end), color: Theme.sleepBadge)
                }.buttonStyle(.pressable)
            }
            ForEach(d.naps) { n in
                ActivityRow(icon: "moon.zzz.fill", value: Fmt.hm(Double(n.asleepSec)), title: "Sieste",
                            start: Fmt.clock(n.start), end: Fmt.clock(n.end), color: Theme.sleepBadge)
            }
            ForEach(d.activities) { a in
                NavigationLink(value: HomeRoute.activity(a.id)) {
                    ActivityRow(icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.name(a),
                                start: Fmt.clock(a.start), end: Fmt.clock(a.end), color: Theme.strainBadge)
                }.buttonStyle(.pressable)
            }
            if d.sleep == nil && d.activities.isEmpty && d.naps.isEmpty {
                CardBox { Text("Aucune activité pour ce jour.").font(WFont.text(15)).foregroundColor(Theme.textSecondary) }
            }
            Text("Les activités sont détectées automatiquement quand ta fréquence cardiaque reste élevée au moins 15 minutes. Tu peux aussi en ajouter ou en enregistrer en direct.")
                .font(WFont.text(11.5)).foregroundColor(Theme.textMuted)
        }
    }
}

struct ActivityDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var date: String
    var activityID: String
    @State private var showType = false
    @State private var points: [HRPoint] = []

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        let a = Self.find(activityID, in: d)
        let maxHR = d.maxHRUsed ?? Double(app.settings.profile.maxHROverride ?? Int(app.settings.profile.tanakaMaxHR))
        DetailScaffold(title: a.map { Sport.name($0) } ?? "Activité",
                       subtitle: a.map { "\(Fmt.clock($0.start)) – \(Fmt.clock($0.end))" }) {
            if let a {
                VStack(spacing: 14) {
                    ScoreRing(progress: (a.strain ?? 0) / 21, color: Theme.strain, lineWidth: 9, size: 156,
                              valueText: Fmt.dec1(a.strain), valueSize: 46)
                    Text("Effort de l'activité").wLabel(11.5)
                }
                .padding(.top, 6)
                .padding(.bottom, 6)

                HStack(spacing: 0) {
                    figure("Durée", Fmt.hm(Double(a.durationSec)), "")
                    divider
                    figure("Calories", Fmt.int(a.calories), "kcal")
                    divider
                    figure("FC moy.", Fmt.int(a.avgHR), "bpm")
                    divider
                    figure("FC max", a.maxHR.map { "\($0)" } ?? "—", "bpm")
                }
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))

                if let route = a.route, route.count >= 2 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Itinéraire").wLabel(11.5)
                            Spacer()
                            if let km = a.distanceKm {
                                Text(String(format: "%.2f km", km).replacingOccurrences(of: ".", with: ","))
                                    .font(WFont.number(16, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        RouteSnapshotMap(route: route)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
                }

                CardBox(title: "Fréquence cardiaque") {
                    if points.count >= 2 {
                        ActivityHRChart(points: points, start: a.start, end: a.end, maxHR: maxHR,
                                        restHR: d.restingHRUsed ?? d.rhr ?? 60)
                    } else {
                        Text(points.isEmpty ? "Pas de fréquence cardiaque enregistrée pendant cette activité." : "")
                            .font(WFont.text(13.5)).foregroundColor(Theme.textSecondary)
                    }
                }
                CardBox(title: "Zones de fréquence cardiaque") { ZoneBars(seconds: a.zoneSeconds) }
                CardBox {
                    Button { showType = true } label: {
                        HStack(spacing: 10) {
                            Text("Type d'activité").wLabel(11.5)
                            Spacer()
                            Image(systemName: Sport.icon(a.sport)).foregroundColor(Theme.textSecondary)
                            Text(Sport.name(a)).font(WFont.text(14, weight: .medium)).foregroundColor(Theme.textSecondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundColor(Theme.textTertiary)
                        }
                    }.buttonStyle(.pressable)
                    if a.source == .auto {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                        Button { Haptics.success(); app.confirmActivity(a, sport: a.sport) } label: {
                            HStack {
                                Text("Confirmer l'activité").wLabel(11.5, color: Theme.optimal)
                                Spacer()
                                Image(systemName: "checkmark.circle").foregroundColor(Theme.optimal)
                            }
                        }.buttonStyle(.pressable)
                    }
                    if a.source != .auto {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                        Button(role: .destructive) {
                            app.deleteActivity(a)
                            dismiss()
                        } label: {
                            Text("Supprimer l'activité").wLabel(11.5, color: Theme.recoveryRed)
                        }.buttonStyle(.pressable)
                    }
                }
                Text(sourceText(a))
                    .font(WFont.text(11.5)).foregroundColor(Theme.textMuted)
            } else {
                CardBox { Text("Activité introuvable.").font(WFont.text(15)).foregroundColor(Theme.textSecondary) }
            }
        }
        .task(id: "\(a?.start ?? 0)-\(a?.end ?? 0)-\(app.dataVersion)") {
            guard let a else { return }
            points = await app.minuteHR(from: a.start, to: a.end)
        }
        .sheet(isPresented: $showType) {
            if let a {
                SportPickerView(selected: a.sport) { app.confirmActivity(a, sport: $0) }
            }
        }
        .onAppear {
            if let pending = app.pendingSportEdit, pending == activityID || a?.id == pending {
                app.pendingSportEdit = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showType = true }
            }
        }
    }

    private var divider: some View { Rectangle().fill(Theme.separator).frame(width: 1, height: 34) }

    private func figure(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 6) {
            Text(title).wLabel(9.5, color: Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(WFont.number(20, weight: .bold)).foregroundColor(.white)
                if !unit.isEmpty && value != "—" { Text(unit).font(WFont.text(9.5, weight: .medium)).foregroundColor(Theme.textSecondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceText(_ a: ActivityRecord) -> String {
        switch a.source {
        case .auto: return "Activité détectée automatiquement. Choisis le sport pour la garder telle quelle."
        case .live: return "Activité enregistrée en direct."
        case .manual: return "Activité ajoutée ou confirmée par toi."
        case .imported: return "Activité importée depuis WHOOP."
        }
    }

    /// By id; else the activity starting closest to the time in the id (auto-detected activities
    /// can shift by a minute once more data arrives, e.g. when opened from a notification).
    static func find(_ id: String, in d: DayMetrics) -> ActivityRecord? {
        if let a = d.activities.first(where: { $0.id == id }) { return a }
        guard let ts = id.split(separator: "-").last.flatMap({ Int($0) }) else { return nil }
        return d.activities.filter { abs($0.start - ts) <= 20 * 60 }.min { abs($0.start - ts) < abs($1.start - ts) }
    }
}

struct AddActivityView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var date: String
    @State private var sport: String = SportRecents.keys.first ?? "course"
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: "Ajouter une activité") { dismiss() }
                ScrollView {
                    VStack(spacing: 16) {
                        CardBox(title: "Activité") { SportChooser(sport: $sport) }
                        CardBox(title: "Horaires") {
                            DatePicker("Début", selection: $start, in: ...Date())
                            DatePicker("Fin", selection: $end, in: start...Date())
                        }
                        .tint(Theme.accentBlue)
                        Text("L'effort, les calories et les zones sont calculés à partir de la fréquence cardiaque enregistrée par ton bracelet pendant ce créneau (sinon, les calories sont estimées selon l'activité et ton poids).")
                            .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
            }
            OutlineButton(title: "Enregistrer") {
                let s = Int(start.timeIntervalSince1970), e = Int(max(end, start.addingTimeInterval(60)).timeIntervalSince1970)
                SportRecents.add(sport)
                app.addActivity(ActivityRecord(id: "manual-\(s)", sport: sport, start: s, end: e, source: .manual))
                dismiss()
            }
            .padding(.horizontal, 44).padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }
}

/// "Sommeil de ce soir": recommended bedtime and the strap's own wake alarm.
struct SleepPlannerView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @Environment(\.dismiss) private var dismiss
    @State private var alarmOn = false
    @State private var alarmTime = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: "Sommeil de ce soir") { dismiss() }
                ScrollView {
                    VStack(spacing: 16) {
                        CardBox(title: "Heure de coucher recommandée") {
                            Text(app.recommendedBedtime.map { Fmt.clock24($0) } ?? "—")
                                .font(WFont.number(54, weight: .bold)).foregroundColor(.white)
                            if let need = app.day(app.today)?.tonightNeedSec {
                                Text("Pour dormir \(Fmt.hmLong(need)) (ton besoin de cette nuit, avec ton efficacité de sommeil habituelle).")
                                    .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                            }
                        }
                        CardBox(title: "Alarme du bracelet") {
                            Toggle(isOn: $alarmOn) {
                                Text("Réveil par vibration").font(WFont.text(16, weight: .semibold)).foregroundColor(.white)
                            }
                            .tint(Theme.recoveryGreen)
                            if alarmOn {
                                DatePicker("Heure", selection: $alarmTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                            }
                            Text(strap.state.isConnected
                                 ? "L'alarme est enregistrée dans le bracelet : il vibre même si ton iPhone est éteint."
                                 : "Connecte ton bracelet pour programmer l'alarme.")
                                .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
            }
            OutlineButton(title: "Enregistrer") {
                let c = DayKey.calendar.dateComponents([.hour, .minute], from: alarmTime)
                app.settings.alarmEnabled = alarmOn
                app.settings.alarmMinute = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                app.applyAlarm()
                dismiss()
            }
            .padding(.horizontal, 44).padding(.bottom, 24)
        }
        .onAppear {
            alarmOn = app.settings.alarmEnabled
            alarmTime = DayKey.calendar.date(bySettingHour: app.settings.alarmMinute / 60, minute: app.settings.alarmMinute % 60, second: 0, of: Date()) ?? Date()
        }
        .preferredColorScheme(.dark)
    }
}
