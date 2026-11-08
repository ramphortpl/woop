import SwiftUI

enum HomeRoute: Hashable {
    case sleep, recovery, strain, activities, activity(String), metric(DashboardMetric), device, outlook
}

/// Accueil. Laid out on the measurements of the WHOOP home screen (393 pt wide).
/// It observes only the app model: strap values (battery, sync, live heart rate) are read by the
/// small views that display them, so a 1 Hz heart rate never redraws the whole screen.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showCustomize = false
    @State private var showAdd = false
    @State private var showStart = false
    @State private var showPlanner = false
    @State private var showSports = false

    var day: DayMetrics { app.selected }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        TopBar()
                            .padding(.leading, 19)
                            .padding(.trailing, 20)
                            .padding(.top, 2)
                        if app.settings.demoMode {
                            Text("Mode démo — données simulées").wLabel(9.5, color: Theme.alarmOrange)
                                .padding(.top, 8)
                        }
                        Wordmark(size: 17).padding(.top, app.settings.demoMode ? 14 : 33)
                        StatusLine().padding(.top, 4)
                        rings.padding(.top, 8)

                        HStack(alignment: .center) {
                            Text("Ma journée").font(WFont.title(20)).foregroundColor(.white)
                            Spacer()
                            Menu {
                                Button { showAdd = true } label: { Label("Ajouter une activité", systemImage: "plus") }
                                Button { showStart = true } label: { Label("Commencer une activité", systemImage: "stopwatch") }
                                Button { showCustomize = true } label: { Label("Personnaliser le tableau de bord", systemImage: "slider.horizontal.3") }
                            } label: {
                                Image(systemName: "plus").font(.system(size: 18, weight: .regular)).foregroundColor(.black)
                                    .frame(width: 35, height: 35)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                            }
                        }
                        .padding(.leading, 21)
                        .padding(.trailing, 18)
                        .padding(.top, 30)

                        VStack(spacing: 16) {
                            NavigationLink(value: HomeRoute.outlook) { outlookRow }.buttonStyle(.pressable)
                            if let live = app.liveSession {
                                Button { showStart = true } label: { LiveSessionBanner(session: live) }.buttonStyle(.pressable)
                            }
                            activitiesCard
                            if app.isToday { tonightCard }
                            dashboard.id("dashboard")
                        }
                        .padding(.horizontal, Theme.side)
                        .padding(.top, 15)
                        .padding(.bottom, 120)
                    }
                }
                .refreshable {
                    StrapManager.shared.syncNow()
                    app.recompute(daysBack: 2)
                }
                .onAppear {
                    switch app.launchScreen {
                    case "dashboard":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { proxy.scrollTo("dashboard", anchor: .top) }
                    case "activity":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showStart = true }
                    case "live":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                            if app.liveSession == nil { app.startLiveSession(sport: "course") }
                            showStart = true
                        }
                    case "sports":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showSports = true }
                    default: break
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withAppRoutes()
        .fullScreenCover(isPresented: $showCustomize) { DashboardCustomizeView() }
        .sheet(isPresented: $showAdd) { AddActivityView(date: app.selectedDate) }
        .fullScreenCover(isPresented: $showStart) { StartActivityView() }
        .sheet(isPresented: $showPlanner) { SleepPlannerView() }
        .sheet(isPresented: $showSports) { SportPickerView(selected: "padel") { _ in } }
    }

    // MARK: Rings

    private var rings: some View {
        let perf = day.sleepPerformance
        let rec = day.recovery
        let strain = day.strain
        return HStack(alignment: .top, spacing: 0) {
            NavigationLink(value: HomeRoute.sleep) {
                ringLabel("Sommeil", progress: (perf ?? 0) / 100, color: Theme.sleep,
                          value: perf.map { "\(Int($0.rounded()))" } ?? "—", suffix: perf == nil ? "" : "%")
            }.buttonStyle(.pressable).frame(maxWidth: .infinity)
            NavigationLink(value: HomeRoute.recovery) {
                ringLabel("Récupération", progress: (rec ?? 0) / 100, color: Theme.recoveryColor(rec),
                          value: rec.map { "\(Int($0.rounded()))" } ?? "—", suffix: rec == nil ? "" : "%",
                          caption: rec == nil ? day.calibrationNights.map { "Calibrage \($0)/\(Recovery.calibrationNights)" } : nil)
            }.buttonStyle(.pressable).frame(maxWidth: .infinity)
            NavigationLink(value: HomeRoute.strain) {
                ringLabel("Effort", progress: (strain ?? 0) / 21, color: Theme.strain,
                          value: strain.map { Fmt.dec1($0) } ?? "—", suffix: "",
                          marker: StrainTarget.optimal(for: rec).map { $0 / 21 })
            }.buttonStyle(.pressable).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 15)
    }

    private func ringLabel(_ title: String, progress: Double, color: Color, value: String, suffix: String,
                           caption: String? = nil, marker: Double? = nil) -> some View {
        VStack(spacing: 0) {
            ScoreRing(progress: progress, color: color, valueText: value, suffix: suffix, marker: marker)
            HStack(spacing: 5) {
                Text(title).wLabel(11.4).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: 0x9EA2A6))
            }
            .padding(.top, 11)
            if let caption {
                Text(caption).font(WFont.text(10, weight: .medium)).foregroundColor(Theme.textSecondary).padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Outlook

    private var outlookRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "sun.max").font(.system(size: 19, weight: .light)).foregroundColor(.white)
                .frame(width: 22)
            let name = app.settings.profile.firstName
            Text(name.isEmpty ? "Perspectives quotidiennes" : "Perspectives quotidiennes de \(name)")
                .font(WFont.text(14.4, weight: .medium)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.leading, 17)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .light)).foregroundColor(Color(hex: 0xA6A9AD))
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .frame(height: 47)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x2F3237)))
    }

    // MARK: Activities

    private var activitiesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activités du jour").wLabel(11.8)
                Spacer()
                NavigationLink(value: HomeRoute.activities) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 16, weight: .light)).foregroundColor(Color(hex: 0xA6A9AD))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.pressable)
                .offset(x: 6)
            }
            .padding(.horizontal, 5)
            .frame(height: 24)

            VStack(spacing: 12) {
                let items = timeline
                if items.isEmpty {
                    Text(app.settings.demoMode || StrapManager.shared.pairedID != nil
                         ? "Aucune activité enregistrée pour ce jour."
                         : "Connecte ton WHOOP pour voir ton sommeil et tes activités.")
                        .font(WFont.text(14)).foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                }
                ForEach(items) { item in
                    NavigationLink(value: item.route) {
                        ActivityRow(icon: item.icon, value: item.value, title: item.title,
                                    start: Fmt.clock(item.start), end: Fmt.clock(item.end), color: item.color)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 14)

            HStack(spacing: 12) {
                CardButton(icon: "plus", text: "Ajouter\nune activité") { showAdd = true }
                CardButton(icon: "stopwatch", text: "Commencer\nactivité") { showStart = true }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 11.5)
        .padding(.top, 13)
        .padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(
            LinearGradient(colors: [Color(hex: 0x2C3033), Color(hex: 0x282B2F)], startPoint: .top, endPoint: .bottom)))
    }

    struct TimelineItem: Identifiable {
        var id: String
        var icon: String
        var value: String
        var title: String
        var start: Int
        var end: Int
        var color: Color
        var route: HomeRoute
    }

    private var timeline: [TimelineItem] {
        var out: [TimelineItem] = []
        if let s = day.sleep {
            out.append(TimelineItem(id: "sleep", icon: "moon.fill", value: Fmt.hm(Double(s.asleepSec)), title: "Sommeil",
                                    start: s.start, end: s.end, color: Theme.sleepBadge, route: .sleep))
        }
        for n in day.naps {
            out.append(TimelineItem(id: "nap-\(n.start)", icon: "moon.zzz.fill", value: Fmt.hm(Double(n.asleepSec)), title: "Sieste",
                                    start: n.start, end: n.end, color: Theme.sleepBadge, route: .sleep))
        }
        for a in day.activities {
            out.append(TimelineItem(id: a.id, icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.name(a),
                                    start: a.start, end: a.end, color: Theme.strainBadge, route: .activity(a.id)))
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Tonight

    private var tonightCard: some View {
        Button { showPlanner = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Sommeil de ce soir").wLabel(11.8)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .light)).foregroundColor(Color(hex: 0xA6A9AD))
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.recommendedBedtime.map { Fmt.clock24($0) } ?? "—")
                            .font(WFont.number(31, weight: .bold)).foregroundColor(.white)
                        Text("Heure de coucher\nrecommandée").wLabel(10.4, color: Color(hex: 0x9EA2A6)).lineSpacing(3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(Fmt.minuteOfDay(app.settings.alarmEnabled ? app.settings.alarmMinute : app.typicalWakeMinute))
                            .font(WFont.number(31, weight: .bold))
                            .foregroundColor(app.settings.alarmEnabled ? .white : Theme.alarmOrange)
                        Text(app.settings.alarmEnabled ? "Alarme\nactivée" : "Alarme\ndésactivée")
                            .wLabel(10.4, color: app.settings.alarmEnabled ? Color(hex: 0x9EA2A6) : Theme.alarmOrange).lineSpacing(3)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.top, 16)
                if let need = day.tonightNeedSec {
                    Text("Besoin de sommeil cette nuit : \(Fmt.hmLong(need))")
                        .font(WFont.text(13, weight: .medium)).foregroundColor(Theme.textSecondary)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
        }
        .buttonStyle(.pressable)
    }

    // MARK: Dashboard

    private var dashboard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mon tableau de bord").font(WFont.title(20)).foregroundColor(.white)
                Spacer()
                Button { showCustomize = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .light)).foregroundColor(Color(hex: 0xA6A9AD))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 14)
            .padding(.leading, 5)
            ForEach(app.settings.dashboard) { m in
                NavigationLink(value: HomeRoute.metric(m)) {
                    if m.isChart {
                        StrainRecoveryTile(date: app.selectedDate)
                    } else {
                        metricRow(m)
                    }
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func metricRow(_ m: DashboardMetric) -> some View {
        let v = m.value(day: day, state: app)
        let base = app.baseline(m, before: app.selectedDate)
        var up: Bool?
        var good: Bool?
        if let v, let base, abs(v - base) > max(0.01, abs(base) * 0.01) {
            up = v > base
            if let hib = m.higherIsBetter { good = (v > base) == hib }
        }
        return MetricRow(icon: m.icon, title: m.title, value: m.format(v), unit: v == nil ? "" : m.unit,
                         baseline: base.map { m.format($0) }, trendUp: up, good: good)
    }
}

/// Avatar with the streak, day navigation and strap battery.
struct TopBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 15))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD54A), Color(hex: 0xFF8A1F), Color(hex: 0xF0412B)], startPoint: .top, endPoint: .bottom))
                    Text("\(app.streak)").font(WFont.number(14, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.leading, 38)
                .padding(.trailing, 11)
                .frame(height: 29)
                .background(Capsule().fill(Color(hex: 0x30383B)))
                .padding(.leading, 6)
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0x86DBD2), Color(hex: 0x4DB5A9)], startPoint: .top, endPoint: .bottom))
                    Text(app.settings.profile.initials).font(WFont.text(12, weight: .bold)).foregroundColor(Color(hex: 0x10302C))
                }
                .frame(width: 29, height: 29)
            }

            Spacer(minLength: 6)

            HStack(spacing: 0) {
                Button { Haptics.select(); app.selectedDate = DayKey.adding(-1, to: app.selectedDate) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundColor(.white).frame(width: 27, height: 29)
                }
                Button { app.selectedDate = app.today } label: {
                    Text(Fmt.dayTitle(app.selectedDate)).wLabel(10.9, tracking: 0.7).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 25)
                        .background(Capsule().fill(Theme.pill))
                }
                Button {
                    guard app.selectedDate < app.today else { return }
                    Haptics.select()
                    app.selectedDate = DayKey.adding(1, to: app.selectedDate)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundColor(app.selectedDate < app.today ? .white : Color(hex: 0x6E7378)).frame(width: 27, height: 29)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 158, height: 29)
            .background(Capsule().fill(Theme.pillOuter))

            Spacer(minLength: 6)

            NavigationLink(value: HomeRoute.device) { StrapStatus() }
                .buttonStyle(.pressable)
        }
    }
}

/// "23 %" and the band glyph (observes the strap: battery and connection change rarely).
struct StrapStatus: View {
    @EnvironmentObject var strap: StrapManager

    var body: some View {
        HStack(spacing: 6) {
            Text(strap.battery.map { "\(Int($0.rounded())) %" } ?? "— %")
                .font(WFont.number(14, weight: .medium)).foregroundColor(Color(hex: 0x91969A))
            StrapGlyph(connected: strap.state.isConnected, charging: strap.charging)
        }
    }
}

/// Sync / computation status under the wordmark (empty when idle).
struct StatusLine: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager

    var body: some View {
        Group {
            if strap.syncing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).tint(Theme.textSecondary)
                    SyncProgressText(progress: strap.progress)
                }
            } else if app.computing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).tint(Theme.textSecondary)
                    Text("Calcul de tes scores…")
                }
            } else if case .failed = strap.state {
                Text("Bracelet : \(strap.state.label)").lineLimit(1)
            }
        }
        .font(WFont.text(11, weight: .medium))
        .foregroundColor(Theme.textSecondary)
        .frame(height: 14)
    }
}

/// Only this text follows the transfer progress.
private struct SyncProgressText: View {
    @ObservedObject var progress: SyncProgress

    var body: some View {
        Text(progress.newest.map { "Synchronisation… données jusqu'au \($0.formatted(date: .abbreviated, time: .shortened))" }
             ?? "Synchronisation du bracelet…")
    }
}

/// Small band glyph with a connection dot.
struct StrapGlyph: View {
    var connected: Bool
    var charging: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white, lineWidth: 1.8).frame(width: 14, height: 23)
                .overlay(RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.9)).frame(width: 4.5, height: 8).offset(x: -2))
            Circle().fill(connected ? Color(hex: 0x3BD36C) : Color(hex: 0x6E7378))
                .frame(width: 6.5, height: 6.5)
                .overlay(Circle().stroke(Theme.bgTop, lineWidth: 1.2))
                .offset(x: 4, y: -3)
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundColor(.yellow).offset(x: 5, y: 13)
            }
        }
        .frame(width: 20, height: 26)
    }
}

/// Live activity in progress (tap to open it).
struct LiveSessionBanner: View {
    var session: LiveSession
    @ObservedObject private var live = StrapManager.shared.live
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Sport.icon(session.sport)).font(.system(size: 21)).foregroundColor(.white)
                .frame(width: 44, height: 44).background(Circle().fill(Theme.strainBadge))
            VStack(alignment: .leading, spacing: 4) {
                Text("En cours · \(Sport.label(session.sport))").wLabel(11.5)
                Text(Fmt.timer(Int(now.timeIntervalSince1970) - session.start))
                    .font(WFont.number(19, weight: .semibold)).foregroundColor(.white).monospacedDigit()
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: 12)).foregroundColor(Theme.recoveryRed)
                Text(live.bpm.map { "\($0)" } ?? "—").font(WFont.number(24, weight: .bold)).foregroundColor(.white)
                Text("BPM").wLabel(9.5, color: Theme.textSecondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.strain.opacity(0.55), lineWidth: 1))
        .onReceive(tick) { now = $0 }
    }
}

/// "Effort et récupération" chart tile: 7 days of strain bars with recovery dots.
struct StrainRecoveryTile: View {
    @EnvironmentObject var app: AppState
    var date: String

    var body: some View {
        let keys = (0..<7).reversed().map { DayKey.adding(-$0, to: date) }
        let days = keys.map { app.day($0) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 17, weight: .light)).foregroundColor(Theme.textSecondary)
                Text("Effort et récupération").wLabel(11.5)
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let strain = days[i]?.strain ?? 0
                    let rec = days[i]?.recovery
                    VStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 96)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.strain.opacity(i == 6 ? 1 : 0.8))
                                .frame(width: 13, height: max(2, CGFloat(strain / 21) * 96))
                            if let rec {
                                Circle().fill(Theme.recoveryColor(rec)).frame(width: 8, height: 8)
                                    .offset(y: -CGFloat(rec / 100) * 88)
                            }
                        }
                        Text(Fmt.shortWeekday(keys[i])).font(WFont.label(9.5)).foregroundColor(i == 6 ? .white : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 14) {
                Label { Text("Effort").font(WFont.text(11, weight: .medium)) } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.strain).frame(width: 10, height: 10)
                }
                Label { Text("Récupération").font(WFont.text(11, weight: .medium)) } icon: {
                    Circle().fill(Theme.recoveryGreen).frame(width: 9, height: 9)
                }
            }
            .foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.cardGradient))
    }
}
