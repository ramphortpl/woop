import SwiftUI
import UserNotifications
import UIKit

/// Plus › Notifications: the WHOOP-style notifications, one switch each.
struct NotificationSettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @ObservedObject private var notifier = Notifier.shared
    @State private var testSent = false

    var body: some View {
        DetailScaffold(title: "Notifications") {
            statusCard

            CardBox(title: "Activités") {
                toggle("Activité détectée", "Après chaque activité détectée automatiquement : sport, horaires, effort, calories. Confirme ou change le sport depuis la notification.", \.activities)
            }
            CardBox(title: "Sommeil et récupération") {
                toggle("Récupération du matin", "Ton score dès que ta nuit est analysée, avec ton effort conseillé.", \.recovery)
                Divider().overlay(Theme.separator)
                toggle("Sommeil", "Ta performance de sommeil (pendant le calibrage de la récupération).", \.sleep)
                Divider().overlay(Theme.separator)
                toggle("Moniteur de santé", "Si plusieurs indicateurs de ta nuit sortent de ta norme.", \.healthMonitor)
                Divider().overlay(Theme.separator)
                toggle("Rappel du coucher", "\(app.settings.notify.bedtimeLeadMinutes) min avant l'heure de coucher recommandée.", \.bedtime)
                if app.settings.notify.bedtime {
                    Stepper("Prévenir \(app.settings.notify.bedtimeLeadMinutes) min avant",
                            value: Binding(get: { app.settings.notify.bedtimeLeadMinutes },
                                           set: { app.settings.notify.bedtimeLeadMinutes = $0 }),
                            in: 10...120, step: 5)
                        .font(WFont.text(14)).foregroundColor(.white)
                }
            }
            CardBox(title: "Effort") {
                toggle("Coach d'effort", "Quand tu atteins ton effort optimal du jour, et si tu le dépasses nettement.", \.strainCoach)
                Divider().overlay(Theme.separator)
                toggle("Bilan de la semaine", "Le lundi à 9:00 : récupération, sommeil, effort et activités.", \.weekly)
            }
            CardBox(title: "Bracelet") {
                toggle("Batterie", "Batterie faible (20 % puis 10 %) et recharge terminée.", \.battery)
                Divider().overlay(Theme.separator)
                toggle("Rappel de synchronisation", "Si ton bracelet ne s'est pas synchronisé depuis 12 h.", \.syncReminder)
            }
            CardBox(title: "Prévenir juste après une activité") {
                Toggle(isOn: Binding(get: { app.settings.continuousHR }, set: {
                    app.settings.continuousHR = $0
                    strap.setBackgroundLive($0)
                })) {
                    Text("Connexion continue au bracelet").font(WFont.text(15, weight: .semibold)).foregroundColor(.white)
                }
                .tint(Theme.recoveryGreen)
                Text("iOS met Woop en veille. Sans cette option, une activité est annoncée à la synchronisation suivante (quand tu ouvres l'app ou quand iOS la réveille). Avec, Woop reste connecté et te prévient quelques minutes après la fin de l'activité, contre un peu plus de batterie du bracelet. Dans les deux cas, ne ferme pas Woop depuis le sélecteur d'apps.")
                    .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OutlineButton(title: "Envoyer une notification test") {
                if notifier.status == .notDetermined { notifier.requestAuthorization() }
                app.sendTestNotification()
                testSent = true
            }
            .padding(.horizontal, 28)
            if testSent {
                Text("Verrouille ton iPhone : la notification arrive dans 5 secondes.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
            }
        }
        .onAppear { notifier.refreshStatus() }
        .onChange(of: app.settings.notify) { _ in app.scheduleTimedNotifications() }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch notifier.status {
        case .denied:
            CardBox {
                Label("Notifications désactivées pour Woop", systemImage: "bell.slash.fill")
                    .font(WFont.text(15, weight: .semibold)).foregroundColor(Theme.recoveryYellow)
                Text("Active-les dans Réglages › Notifications › Woop pour recevoir tes activités et ta récupération.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Ouvrir les Réglages").wLabel(12.5, color: Theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
        case .notDetermined:
            CardBox {
                Text("Woop peut te prévenir comme l'app WHOOP : activités détectées, récupération du matin, effort cible, heure du coucher.")
                    .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { notifier.requestAuthorization() } label: {
                    Text("Autoriser les notifications").wLabel(12.5, color: Theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
        default:
            CardBox {
                Label("Notifications activées", systemImage: "bell.badge.fill")
                    .font(WFont.text(15, weight: .semibold)).foregroundColor(Theme.recoveryGreen)
            }
        }
    }

    private func toggle(_ title: String, _ detail: String, _ kp: WritableKeyPath<NotifyPrefs, Bool>) -> some View {
        Toggle(isOn: Binding(get: { app.settings.notify[keyPath: kp] }, set: { app.settings.notify[keyPath: kp] = $0 })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(WFont.text(15, weight: .semibold)).foregroundColor(.white)
                Text(detail).font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.recoveryGreen)
    }
}
