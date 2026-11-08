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
                    ActivityRow(icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.label(a.sport),
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
        let a = d.activities.first { $0.id == activityID }
        DetailScaffold(title: a.map { Sport.label($0.sport) } ?? "Activité", subtitle: a.map { "\(Fmt.clock($0.start)) – \(Fmt.clock($0.end))" }) {
            if let a {
                ScoreRing(progress: (a.strain ?? 0) / 21, color: Theme.strain, lineWidth: 14, size: 170,
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
                        HStack {
                            Text("Type d'activité").wLabel(12.5)
                            Spacer()
                            Text(Sport.label(a.sport)).foregroundColor(Theme.textSecondary)
                            Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                        }
                    }.buttonStyle(.plain)
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
                .confirmationDialog("Type d'activité", isPresented: $showType) {
                    ForEach(Sport.allCases) { s in
                        Button(s.label) { retype(a, s) }
                    }
                }
                Text(a.source == .auto ? "Activité détectée automatiquement." : (a.source == .live ? "Activité enregistrée en direct." : "Activité ajoutée manuellement."))
                    .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
            } else {
                CardBox { Text("Activité introuvable.").foregroundColor(Theme.textSecondary) }
            }
        }
    }

    /// Changing the type of an auto-detected activity turns it into a saved manual one.
    private func retype(_ a: ActivityRecord, _ s: Sport) {
        var n = a
        n.sport = s.rawValue
        if n.source == .auto {
            n.id = "manual-\(a.start)"
            n.source = .manual
        } else {
            app.deleteActivity(a)
        }
        app.addActivity(n)
    }
}

struct AddActivityView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var date: String
    @State private var sport: Sport = .course
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: "Ajouter une activité") { dismiss() }
                ScrollView {
                    VStack(spacing: 16) {
                        CardBox(title: "Type") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(Sport.allCases) { s in
                                    Button { sport = s } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: s.icon).font(.system(size: 22))
                                            Text(s.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                        }
                                        .foregroundColor(sport == s ? .black : .white)
                                        .frame(maxWidth: .infinity, minHeight: 70)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(sport == s ? Color.white : Theme.cardInner.opacity(0.6)))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        CardBox(title: "Horaires") {
                            DatePicker("Début", selection: $start, in: ...Date())
                            DatePicker("Fin", selection: $end, in: start...Date())
                        }
                        .tint(Theme.accentBlue)
                        Text("L'effort, les calories et les zones sont calculés à partir de la fréquence cardiaque enregistrée par ton bracelet pendant ce créneau.")
                            .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
            }
            OutlineButton(title: "Enregistrer") {
                let s = Int(start.timeIntervalSince1970), e = Int(max(end, start.addingTimeInterval(60)).timeIntervalSince1970)
                app.addActivity(ActivityRecord(id: "manual-\(s)", sport: sport.rawValue, start: s, end: e, source: .manual))
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
    @State private var sport: Sport = .course
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(Sport.allCases) { s in
                                Button { sport = s } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: s.icon).font(.system(size: 24))
                                        Text(s.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    .foregroundColor(sport == s ? .black : .white)
                                    .frame(maxWidth: .infinity, minHeight: 78)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(sport == s ? Color.white : Theme.cardInner.opacity(0.6)))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 120)
                    }
                }
            }
            if app.liveSession == nil {
                OutlineButton(title: "Démarrer") {
                    app.startLiveSession(sport: sport.rawValue)
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
