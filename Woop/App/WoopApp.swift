import SwiftUI

@main
struct WoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // Singletons held as plain constants: observing them here would re-evaluate the whole scene
    // on every change. Views observe what they display through the environment.
    private let app = AppState.shared
    private let strap = StrapManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(strap)
                .environmentObject(Chrome.shared)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .environment(\.font, WFont.text(15))
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

/// Which tab a screen belongs to (each tab keeps its own navigation stack alive).
private struct TabIDKey: EnvironmentKey { static let defaultValue: MainTab = .home }
extension EnvironmentValues {
    var tabID: MainTab {
        get { self[TabIDKey.self] }
        set { self[TabIDKey.self] = newValue }
    }
}

/// Window chrome state: how many detail screens are pushed in each tab (the tab bar hides on
/// detail screens, like in the WHOOP app; the coach button stays).
final class Chrome: ObservableObject {
    static let shared = Chrome()
    @Published private(set) var depth: [MainTab: Int] = [:]

    func push(_ t: MainTab) { depth[t, default: 0] += 1 }
    func pop(_ t: MainTab) { depth[t] = max(0, depth[t, default: 0] - 1) }
    func isDetail(_ t: MainTab) -> Bool { depth[t, default: 0] > 0 }
}

private struct HidesTabBar: ViewModifier {
    @Environment(\.tabID) private var tab

    func body(content: Content) -> some View {
        content
            .onAppear { Chrome.shared.push(tab) }
            .onDisappear { Chrome.shared.pop(tab) }
    }
}

extension View {
    /// Detail screens: hide the tab bar while shown.
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: MainTab = .home
    @State private var visited: Set<MainTab> = [.home]
    @State private var showCoach = false
    @State private var showCustomize = false
    @State private var showPlanner = false
    @State private var homePath: [HomeRoute] = []

    var body: some View {
        Group {
            if !app.settings.onboardingDone {
                OnboardingView()
            } else {
                ZStack(alignment: .bottom) {
                    ScreenBackground()
                    // Every visited tab stays alive: switching is instant and keeps its scroll
                    // position and navigation, as in the WHOOP app.
                    ZStack {
                        page(.home) { NavigationStack(path: $homePath) { HomeView() } }
                        page(.health) { NavigationStack { HealthView() } }
                        page(.community) { NavigationStack { CommunityView() } }
                        page(.more) { NavigationStack { MoreView() } }
                    }
                    TabBarContainer(tab: $tab, onSelect: select, onCoach: { showCoach = true })
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

    @ViewBuilder
    private func page<Content: View>(_ t: MainTab, @ViewBuilder _ content: () -> Content) -> some View {
        if visited.contains(t) {
            content()
                .environment(\.tabID, t)
                .opacity(tab == t ? 1 : 0)
                .allowsHitTesting(tab == t)
                .accessibilityHidden(tab != t)
        }
    }

    private func select(_ t: MainTab) {
        if t == tab {
            // Second tap on the current tab: back to its root.
            if t == .home { withAnimation(.easeInOut(duration: 0.25)) { homePath = [] } }
            return
        }
        visited.insert(t)
        tab = t
    }

    /// Go where a tapped notification points.
    private func openLink(_ link: DeepLink?) {
        guard let link else { return }
        app.deepLink = nil
        showCoach = false
        showCustomize = false
        switch link {
        case .home:
            select(.home)
            homePath = []
        case let .route(day, route):
            select(.home)
            app.selectedDate = day
            homePath = [route]
        case .planner:
            select(.home)
            homePath = []
            showPlanner = true
        case .tab(let t):
            select(t)
        }
    }

    /// CI screenshot of an activity: open the first one of the day once the demo is computed.
    private func openFirstActivity(attempt: Int) {
        if let a = app.selected.activities.first {
            homePath = [.activity(a.id)]
            return
        }
        guard attempt < 25 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { openFirstActivity(attempt: attempt + 1) }
    }

    /// `-woopScreen` launch argument: open a given screen directly (used for CI screenshots).
    private func applyLaunchScreen() {
        switch app.launchScreen {
        case "health": select(.health)
        case "community": select(.community)
        case "more": select(.more)
        case "customize": DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCustomize = true }
        case "coach": DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCoach = true }
        case "sleep", "sleep2": homePath = [.sleep]
        case "workout": openFirstActivity(attempt: 0)
        case "recovery": homePath = [.recovery]
        case "strain": homePath = [.strain]
        case "device": homePath = [.device]
        case "notifications", "import": select(.more)
        default: break
        }
    }
}

/// Hides the tab capsule on detail screens (only this small view observes the navigation depth).
private struct TabBarContainer: View {
    @EnvironmentObject var chrome: Chrome
    @Binding var tab: MainTab
    var onSelect: (MainTab) -> Void
    var onCoach: () -> Void

    var body: some View {
        TabBar(tab: tab, showTabs: !chrome.isDetail(tab), onSelect: onSelect, onCoach: onCoach)
            .padding(.leading, 12)
            .padding(.trailing, 13)
            .padding(.bottom, -6)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: chrome.isDetail(tab))
    }
}

/// Floating capsule (Accueil · Santé · Communauté · Plus) and the round coach button.
struct TabBar: View {
    var tab: MainTab
    var showTabs: Bool
    var onSelect: (MainTab) -> Void
    var onCoach: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showTabs {
                HStack(spacing: 0) {
                    item(.home, "house", "Accueil")
                    item(.health, "heart", "Santé")
                    item(.community, "person.3", "Communauté")
                    item(.more, "line.3.horizontal", "Plus")
                }
                .padding(.horizontal, 6)
                .frame(height: 62)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color(hex: 0x1D2126).opacity(0.72)))
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .environment(\.colorScheme, .dark)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer()
            }
            CoachButton(action: onCoach)
        }
    }

    private func item(_ t: MainTab, _ icon: String, _ label: String) -> some View {
        Button {
            Haptics.select()
            onSelect(t)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 21, weight: tab == t ? .regular : .light))
                    .frame(height: 23)
                Text(label).font(WFont.text(10.8, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(tab == t ? .white : Color(hex: 0x888C90))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The round "W" coach button with its gradient ring.
struct CoachButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Color(hex: 0x262A40).opacity(0.75))
                Circle()
                    .stroke(AngularGradient(colors: [Color(hex: 0x9C84F5), Color(hex: 0x5A8CF0), Color(hex: 0x6FD3F0), Color(hex: 0x9C84F5)], center: .center), lineWidth: 2.2)
                    .padding(13)
                Text("W").font(.system(size: 16, weight: .light)).foregroundColor(.white)
            }
            .frame(width: 62, height: 62)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Coach")
    }
}
