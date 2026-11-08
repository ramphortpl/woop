import SwiftUI

enum HomeRoute: Hashable {
    case sleep, recovery, strain, activities, activity(String), metric(DashboardMetric), device, outlook
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @State private var showCustomize = false
    @State private var showAdd = false
    @State private var showStart = false
    @State private var showPlanner = false

    var day: DayMetrics { app.selected }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TopBar()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    if app.settings.demoMode {
                        Text("Mode démo — données simulées").wLabel(10, color: Theme.alarmOrange)
                            .padding(.top, 8)
                    }
                    Wordmark().padding(.top, 18)
                    StatusLine().padding(.top, 6)
                    rings.padding(.top, 22)

                    HStack {
                        Text("Ma journée").font(.system(size: 26, weight: .medium)).foregroundColor(.white)
                        Spacer()
                        Menu {
                            Button { showAdd = true } label: { Label("Ajouter une activité", systemImage: "plus") }
                            Button { showStart = true } label: { Label("Commencer une activité", systemImage: "stopwatch") }
                            Button { showCustomize = true } label: { Label("Personnaliser le tableau de bord", systemImage: "slider.horizontal.3") }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundColor(.black)
                                .frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)

                    VStack(spacing: 18) {
                        NavigationLink(value: HomeRoute.outlook) { outlookRow }.buttonStyle(.plain)
                        if let live = app.liveSession { LiveSessionBanner(session: live) }
                        activitiesCard
                        if app.isToday { tonightCard }
                        dashboard.id("dashboard")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .refreshable {
                strap.syncNow()
                app.recompute(daysBack: 2)
            }
            .onAppear {
                if app.launchScreen == "dashboard" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { proxy.scrollTo("dashboard", anchor: .top) }
                }
            }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .withAppRoutes()
        .fullScreenCover(isPresented: $showCustomize) { DashboardCustomizeView() }
        .sheet(isPresented: $showAdd) { AddActivityView(date: app.selectedDate) }
        .sheet(isPresented: $showStart) { StartActivityView() }
        .sheet(isPresented: $showPlanner) { SleepPlannerView() }
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
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            NavigationLink(value: HomeRoute.recovery) {
                ringLabel("Récupération", progress: (rec ?? 0) / 100, color: Theme.recoveryColor(rec),
                          value: rec.map { "\(Int($0.rounded()))" } ?? "—", suffix: rec == nil ? "" : "%",
                          caption: rec == nil ? day.calibrationNights.map { "Calibrage \($0)/\(Recovery.calibrationNights)" } : nil)
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            NavigationLink(value: HomeRoute.strain) {
                ringLabel("Effort", progress: (strain ?? 0) / 21, color: Theme.strain,
                          value: strain.map { Fmt.dec1($0) } ?? "—", suffix: "")
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
    }

    private func ringLabel(_ title: String, progress: Double, color: Color, value: String, suffix: String, caption: String? = nil) -> some View {
        VStack(spacing: 11) {
            ScoreRing(progress: progress, color: color, valueText: value, suffix: suffix)
            HStack(spacing: 3) {
                Text(title).wLabel(11.5, tracking: 1.3).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
            }
            if let caption { Text(caption).font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textSecondary) }
        }
    }

    // MARK: Outlook

    private var outlookRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max").font(.system(size: 19)).foregroundColor(.white)
            let name = app.settings.profile.firstName
            Text(name.isEmpty ? "Perspectives quotidiennes" : "Perspectives quotidiennes de \(name)")
                .font(.system(size: 16, weight: .regular)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
    }

    // MARK: Activities

    private var activitiesCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Activités du jour").wLabel(12.5, tracking: 1.5)
                Spacer()
                NavigationLink(value: HomeRoute.activities) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 18)).foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            let items = timeline
            if items.isEmpty {
                Text(app.settings.demoMode || strap.pairedID != nil
                     ? "Aucune activité enregistrée pour ce jour."
                     : "Connecte ton WHOOP pour voir ton sommeil et tes activités.")
                    .font(.system(size: 14)).foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            ForEach(items) { item in
                NavigationLink(value: item.route) {
                    ActivityRow(icon: item.icon, value: item.value, title: item.title,
                                start: Fmt.clock(item.start), end: Fmt.clock(item.end), color: item.color)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                CardButton(icon: "plus", text: "Ajouter\nune activité") { showAdd = true }
                CardButton(icon: "stopwatch", text: "Commencer\nactivité") { showStart = true }
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardGradient))
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
            out.append(TimelineItem(id: a.id, icon: Sport.icon(a.sport), value: Fmt.dec1(a.strain), title: Sport.label(a.sport),
                                    start: a.start, end: a.end, color: Theme.strainBadge, route: .activity(a.id)))
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Tonight

    private var tonightCard: some View {
        Button { showPlanner = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Sommeil de ce soir").wLabel(12.5, tracking: 1.5)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textSecondary)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.recommendedBedtime.map { Fmt.clock24($0) } ?? "—")
                            .font(WFont.number(34, weight: .bold)).foregroundColor(.white)
                        Text("Heure de coucher\nrecommandée").wLabel(11, color: Theme.textSecondary, tracking: 1.2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Fmt.minuteOfDay(app.settings.alarmEnabled ? app.settings.alarmMinute : app.typicalWakeMinute))
                            .font(WFont.number(34, weight: .bold))
                            .foregroundColor(app.settings.alarmEnabled ? .white : Theme.alarmOrange.opacity(0.85))
                        Text(app.settings.alarmEnabled ? "Alarme\nactivée" : "Alarme\ndésactivée")
                            .wLabel(11, color: app.settings.alarmEnabled ? Theme.textSecondary : Theme.alarmOrange, tracking: 1.2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let need = day.tonightNeedSec {
                    Text("Besoin de sommeil cette nuit : \(Fmt.hmLong(need))")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textSecondary)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardGradient))
        }
        .buttonStyle(.plain)
    }

    // MARK: Dashboard

    private var dashboard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mon tableau de bord").font(.system(size: 22, weight: .medium)).foregroundColor(.white)
                Spacer()
                Button { showCustomize = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).foregroundColor(Theme.textSecondary)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.top, 14)
            ForEach(app.settings.dashboard) { m in
                NavigationLink(value: HomeRoute.metric(m)) {
                    if m.isChart {
                        StrainRecoveryTile(date: app.selectedDate)
                    } else {
                        metricRow(m)
                    }
                }
                .buttonStyle(.plain)
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

/// Avatar, streak, date navigation and strap battery.
struct TopBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0x6EDBCB), Color(hex: 0x3FB3A6)], startPoint: .top, endPoint: .bottom))
                    Text(app.settings.profile.initials).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x10302C))
                }
                .frame(width: 42, height: 42)
                .zIndex(1)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    Text("\(app.streak)").font(WFont.number(19, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.leading, 18).padding(.trailing, 12)
                .frame(height: 38)
                .background(Capsule().fill(Theme.card))
            }

            HStack(spacing: 0) {
                Button { app.selectedDate = DayKey.adding(-1, to: app.selectedDate) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundColor(.white).frame(width: 30, height: 38)
                }
                Button { app.selectedDate = app.today } label: {
                    Text(Fmt.dayTitle(app.selectedDate)).wLabel(12.5, tracking: 1.6).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(Theme.cardInner.opacity(0.6)))
                }
                Button {
                    if app.selectedDate < app.today { app.selectedDate = DayKey.adding(1, to: app.selectedDate) }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
                        .foregroundColor(app.selectedDate < app.today ? .white : Theme.textTertiary).frame(width: 30, height: 38)
                }
            }
            .frame(height: 38)
            .background(Capsule().fill(Theme.card))

            NavigationLink(value: HomeRoute.device) {
                HStack(spacing: 6) {
                    Text(strap.battery.map { "\(Int($0.rounded())) %" } ?? "— %")
                        .font(WFont.number(18, weight: .medium)).foregroundColor(Theme.textSecondary)
                    StrapGlyph(connected: strap.state.isConnected, charging: strap.charging)
                }
            }
            .buttonStyle(.plain)
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
                    ProgressView().scaleEffect(0.7).tint(Theme.textSecondary)
                    Text(strap.syncNewest.map { "Synchronisation… données jusqu'au \($0.formatted(date: .abbreviated, time: .shortened))" }
                         ?? "Synchronisation du bracelet…")
                }
            } else if app.computing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(Theme.textSecondary)
                    Text("Calcul de tes scores…")
                }
            } else if case .failed = strap.state {
                Text("Bracelet : \(strap.state.label)").lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Theme.textSecondary)
        .frame(height: 16)
    }
}

/// Small band glyph with a connection dot.
struct StrapGlyph: View {
    var connected: Bool
    var charging: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: 2).frame(width: 15, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.9)).frame(width: 5, height: 9).offset(x: -2))
            Circle().fill(connected ? Theme.recoveryGreen : Theme.textTertiary).frame(width: 7, height: 7).offset(x: 4, y: -3)
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundColor(.yellow).offset(x: 5, y: 14)
            }
        }
        .frame(width: 22, height: 30)
    }
}

/// "WOOP" wordmark in the thin geometric style of the original.
struct Wordmark: View {
    var body: some View {
        Text("WOOP")
            .font(.system(size: 24, weight: .light, design: .default))
            .tracking(3.5)
            .foregroundColor(.white)
    }
}

/// Live activity in progress.
struct LiveSessionBanner: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    var session: LiveSession
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Sport.icon(session.sport)).font(.system(size: 24)).foregroundColor(.white)
                .frame(width: 48, height: 48).background(Circle().fill(Theme.strainBadge))
            VStack(alignment: .leading, spacing: 3) {
                Text(Sport.label(session.sport)).wLabel(13)
                Text(Fmt.hm(now.timeIntervalSince1970 - Double(session.start)) + " · " + (strap.liveHR.map { "\($0) bpm" } ?? "— bpm"))
                    .font(WFont.number(18, weight: .semibold)).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button { app.endLiveSession(save: true) } label: {
                Text("Terminer").wLabel(12, color: .black, tracking: 1).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.strain.opacity(0.6), lineWidth: 1))
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
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundColor(Theme.textSecondary)
                Text("Effort et récupération").wLabel(12)
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let strain = days[i]?.strain ?? 0
                    let rec = days[i]?.recovery
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 96)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.strain)
                                .frame(width: 14, height: max(2, CGFloat(strain / 21) * 96))
                            if let rec {
                                Circle().fill(Theme.recoveryColor(rec)).frame(width: 8, height: 8)
                                    .offset(y: -CGFloat(rec / 100) * 88)
                            }
                        }
                        Text(Fmt.shortWeekday(keys[i])).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 14) {
                Label { Text("Effort").font(.system(size: 11, weight: .semibold)) } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.strain).frame(width: 10, height: 10)
                }
                Label { Text("Récupération").font(.system(size: 11, weight: .semibold)) } icon: {
                    Circle().fill(Theme.recoveryGreen).frame(width: 9, height: 9)
                }
            }
            .foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardGradient))
    }
}
