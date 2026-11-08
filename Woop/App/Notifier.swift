import Foundation
import UIKit
import UserNotifications

/// Local notifications (WHOOP-style): posting, scheduling, and what happens when one is tapped.
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    static let activityCategory = "WOOP_ACTIVITY"
    static let actionConfirm = "WOOP_CONFIRM"
    static let actionChange = "WOOP_CHANGE"

    private var center: UNUserNotificationCenter { .current() }

    /// Must run at launch (before a tap on a notification is delivered).
    func setup() {
        center.delegate = self
        let confirm = UNNotificationAction(identifier: Self.actionConfirm, title: "Confirmer", options: [])
        let change = UNNotificationAction(identifier: Self.actionChange, title: "Changer de sport", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.activityCategory, actions: [confirm, change], intentIdentifiers: [], options: []),
        ])
        refreshStatus()
    }

    func refreshStatus() {
        center.getNotificationSettings { s in
            DispatchQueue.main.async { self.status = s.authorizationStatus }
        }
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async {
                self.refreshStatus()
                done?(ok)
            }
        }
    }

    func post(_ p: PlannedNotification, after delay: TimeInterval = 0) {
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        center.add(UNNotificationRequest(identifier: p.id, content: content(p), trigger: trigger))
    }

    func schedule(_ p: PlannedNotification, at date: Date) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: p.id, content: content(p), trigger: trigger))
    }

    func cancel(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func content(_ p: PlannedNotification) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = p.title
        c.body = p.body
        c.sound = .default
        c.threadIdentifier = p.thread
        c.userInfo = ["route": p.route]
        if p.activityActions { c.categoryIdentifier = Self.activityCategory }
        c.interruptionLevel = .active
        switch p.kind {
        case .recovery, .activity: c.relevanceScore = 1
        case .sleep, .strainTarget, .strainOver, .health: c.relevanceScore = 0.7
        default: c.relevanceScore = 0.4
        }
        return c
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown as a banner even while Woop is open (like WHOOP).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in
            AppState.shared.handleNotification(route: route, action: action)
            completionHandler()
        }
    }
}

/// App delegate: notifications and Bluetooth state restoration need the app model started at
/// launch, including when iOS relaunches Woop in the background.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Notifier.shared.setup()
        AppState.shared.start()
        return true
    }
}
