import SwiftUI

@main
struct WoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared
    @StateObject private var strap = StrapManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(strap)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .onAppear { app.start() }
                // "Partager › Woop" / "Ouvrir avec Woop" on the WHOOP export.
                .onOpenURL { url in app.handleOpenedFile(url) }
        }
        .onChange(of: scenePhase) { phase in
            strap.setForeground(phase == .active)
            if phase == .active {
                app.recompute(daysBack: 2)
                app.importDropFolderIfNeeded()
                Notifier.shared.refreshStatus()
            }
            if phase == .background { app.scheduleBackgroundRefresh() }
        }
        .backgroundTask(.appRefresh(AppState.refreshTaskID)) {
            await AppState.shared.backgroundRefresh()
        }
    }
}

enum MainTab: Hashable { case home, health, community, more }

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: MainTab = .home
    @State private var showCoach = false

    var body: some View {
        Group {
            if !app.settings.onboardingDone {
                OnboardingView()
            } else {
                ZStack(alignment: .bottom) {
                    ScreenBackground()
                    Group {
                        switch tab {
                        case .home: NavigationStack(path: $homePath) { HomeView() }
                        case .health: NavigationStack { HealthView() }
                        case .community: NavigationStack { CommunityView() }
                        case .more: NavigationStack { MoreView() }
                        }
                    }
                    TabBar(tab: $tab, onCoach: { showCoach = true })
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                }
                .ignoresSafeArea(.keyboard)
                .sheet(isPresented: $showCoach) { CoachView() }
                .sheet(isPresented: $showPlanner) { SleepPlannerView() }
                .fullScreenCover(isPresented: $showCustomize) { DashboardCustomizeView() }
                .onAppear {
                    applyLaunchScreen()
                    openLink(app.deepLink)
                }
                .onChange(of: app.deepLink) { openLink($0) }
            }
        }
        .alert(item: $app.importOutcome) { o in
            Alert(title: Text(o.title), message: Text(o.message), dismissButton: .default(Text("OK")))
        }
    }

    @State private var showCustomize = false
    @State private var showPlanner = false
    @State private var homePath: [HomeRoute] = []

    /// Go where a tapped notification points.
    private func openLink(_ link: DeepLink?) {
        guard let link else { return }
        app.deepLink = nil
        showCoach = false
        showCustomize = false
        switch link {
        case .home:
            tab = .home
            homePath = []
        case let .route(day, route):
            tab = .home
            app.selectedDate = day
            homePath = [route]
        case .planner:
            tab = .home
            homePath = []
            showPlanner = true
        case .tab(let t):
            tab = t
        }
    }

    /// `-woopScreen` launch argument: open a given screen directly (used for CI screenshots).
    private func applyLaunchScreen() {
        switch app.launchScreen {
        case "health": tab = .health
        case "community": tab = .community
        case "more": tab = .more
        case "customize": DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCustomize = true }
        case "coach": DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCoach = true }
        case "sleep": homePath = [.sleep]
        case "recovery": homePath = [.recovery]
        case "strain": homePath = [.strain]
        case "device": homePath = [.device]
        case "notifications", "import": tab = .more
        default: break
        }
    }
}

struct TabBar: View {
    @Binding var tab: MainTab
    var onCoach: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                item(.home, "house", "Accueil")
                item(.health, "heart.text.square", "Santé")
                item(.community, "person.3", "Communauté")
                item(.more, "line.3.horizontal", "Plus")
            }
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .environment(\.colorScheme, .dark)

            Button(action: onCoach) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().stroke(AngularGradient(colors: [Theme.coachPurple, Theme.strain, Theme.teal, Theme.coachPurple], center: .center), lineWidth: 2.5)
                        .padding(9)
                    Text("W").font(.system(size: 17, weight: .light, design: .rounded)).foregroundColor(.white)
                }
                .frame(width: 66, height: 66)
                .environment(\.colorScheme, .dark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coach")
        }
    }

    private func item(_ t: MainTab, _ icon: String, _ label: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 21, weight: tab == t ? .semibold : .regular))
                Text(label).font(.system(size: 11, weight: tab == t ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(tab == t ? .white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
