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
                }.buttonStyle(.plain)
            }
            ForEach(d.naps) { n in
                ActivityRow(icon: "moon.zzz.fill", value: Fmt.hm(Double(n.asleepSec)), title: "Sieste",
                            start: Fmt.clock(n.start), end: Fmt.clock(n.end), color: Theme.sleepBadge)
            }
            ForEach(d.activities) { a in
                NavigationLink(value: HomeRoute.activity(a.id)) {
                    ActivityRow(icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.name(a),
                                start: Fmt.clock(a.start), end: Fmt.clock(a.end), color: Theme.strainBadge)
                }.buttonStyle(.plain)
            }
            if d.sleep == nil && d.activities.isEmpty && d.naps.isEmpty {
                CardBox { Text("Aucune activité pour ce jour.").foregroundColor(Theme.textSecondary) }
            }
            Text("Les activités sont détectées automatiquement quand ta fréquence cardiaque reste élevée au moins 15 minutes. Tu peux aussi en ajouter ou en enregistrer en direct.")
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
        }
    }
}

struct ActivityDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var date: String
    var activityID: String
    @State private var showType = false

    var body: some View {
        let d = app.day(date) ?? .empty(date)
        let a = Self.find(activityID, in: d)
        DetailScaffold(title: a.map { Sport.name($0) } ?? "Activité", subtitle: a.map { "\(Fmt.clock($0.start)) – \(Fmt.clock($0.end))" }) {
            if let a {
                ScoreRing(progress: (a.strain ?? 0) / 21, color: Theme.strain, lineWidth: 10, size: 170,
                          valueText: Fmt.dec1(a.strain), valueSize: 56)
                Text("Effort de l'activité").wLabel(12, color: Theme.textSecondary)
                TileGrid(tiles: [
                    StatTile(title: "Durée", value: Fmt.hm(Double(a.durationSec))),
                    StatTile(title: "Calories", value: Fmt.int(a.calories), unit: "kcal"),
                    StatTile(title: "FC moyenne", value: Fmt.int(a.avgHR), unit: "bpm"),
                    StatTile(title: "FC max", value: Fmt.int(a.maxHR.map(Double.init)), unit: "bpm"),
                ])
                CardBox(title: "Zones de fréquence cardiaque") { ZoneBars(seconds: a.zoneSeconds) }
                CardBox {
                    Button { showType = true } label: {
                        HStack(spacing: 10) {
                            Text("Type d'activité").wLabel(12.5)
                            Spacer()
                            Image(systemName: Sport.icon(a.sport)).foregroundColor(Theme.textSecondary)
                            Text(Sport.name(a)).foregroundColor(Theme.textSecondary).lineLimit(1)
                            Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                        }
                    }.buttonStyle(.plain)
                    if a.source == .auto {
                        Divider().overlay(Theme.separator)
                        Button { app.confirmActivity(a, sport: a.sport) } label: {
                            HStack {
                                Text("Confirmer l'activité").wLabel(12.5, color: Theme.recoveryGreen)
                                Spacer()
                                Image(systemName: "checkmark.circle").foregroundColor(Theme.recoveryGreen)
                            }
                        }.buttonStyle(.plain)
                    }
                    if a.source != .auto {
                        Divider().overlay(Theme.separator)
                        Button(role: .destructive) {
                            app.deleteActivity(a)
                            dismiss()
                        } label: {
                            Text("Supprimer l'activité").wLabel(12.5, color: Theme.recoveryRed)
                        }.buttonStyle(.plain)
                    }
                }
                Text(sourceText(a))
                    .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
            } else {
                CardBox { Text("Activité introuvable.").foregroundColor(Theme.textSecondary) }
            }
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
                            .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
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

struct StartActivityView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @Environment(\.dismiss) private var dismiss
    @State private var sport: String = SportRecents.keys.first ?? "course"
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: app.liveSession == nil ? "Commencer une activité" : "Activité en cours") { dismiss() }
                if let live = app.liveSession {
                    Spacer()
                    VStack(spacing: 18) {
                        Image(systemName: Sport.icon(live.sport)).font(.system(size: 44)).foregroundColor(.white)
                        Text(Sport.label(live.sport)).wLabel(16)
                        Text(Fmt.hm(now.timeIntervalSince1970 - Double(live.start)))
                            .font(WFont.number(72, weight: .bold)).foregroundColor(.white)
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill").foregroundColor(Theme.recoveryRed)
                            Text(strap.liveHR.map { "\($0)" } ?? "—").font(WFont.number(44, weight: .bold)).foregroundColor(.white)
                            Text("bpm").foregroundColor(Theme.textSecondary)
                        }
                        if !strap.state.isConnected {
                            Text("Bracelet non connecté : la fréquence cardiaque sera récupérée à la prochaine synchronisation.")
                                .font(.system(size: 12)).foregroundColor(Theme.alarmOrange).multilineTextAlignment(.center).padding(.horizontal, 30)
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button { app.endLiveSession(save: false); dismiss() } label: {
                            Text("Annuler").wLabel(13, color: Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 56)
                                .background(Capsule().stroke(Theme.textTertiary, lineWidth: 1.5))
                        }
                        Button { app.endLiveSession(save: true); dismiss() } label: {
                            Text("Terminer").wLabel(13, color: .black).frame(maxWidth: .infinity, minHeight: 56)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24).padding(.bottom, 30)
                } else {
                    ScrollView {
                        CardBox(title: "Activité") { SportChooser(sport: $sport) }
                            .padding(16)
                            .padding(.bottom, 120)
                    }
                }
            }
            if app.liveSession == nil {
                OutlineButton(title: "Démarrer") {
                    SportRecents.add(sport)
                    app.startLiveSession(sport: sport)
                }
                .padding(.horizontal, 44).padding(.bottom, 24)
            }
        }
        .onReceive(tick) { now = $0 }
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
                                    .font(.system(size: 13)).foregroundColor(Theme.textSecondary)
                            }
                        }
                        CardBox(title: "Alarme du bracelet") {
                            Toggle(isOn: $alarmOn) {
                                Text("Réveil par vibration").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
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
                                .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
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
