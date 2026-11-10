import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @ObservedObject private var live = StrapManager.shared.live
    @ObservedObject private var progress = StrapManager.shared.progress
    @State private var confirmForget = false

    var body: some View {
        DetailScaffold(title: "Mon bracelet", subtitle: strap.strapName ?? strap.model) {
            statusCard
            FirmwareNotice()
            if strap.pairedID == nil || !strap.state.isConnected {
                PairingCard()
            }
            if strap.pairedID != nil {
                CardBox(title: "Synchronisation") {
                    row("Dernière synchronisation", Fmt.relative(strap.lastSync))
                    if strap.syncing {
                        HStack {
                            ProgressView().tint(.white)
                            Text("Transfert en cours… \(Fmt.int(Double(progress.seconds))) s de données")
                                .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                        }
                        if let n = progress.newest {
                            Text("Données jusqu'au \(n.formatted(date: .abbreviated, time: .shortened))")
                                .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                        }
                    }
                    Button { strap.syncNow() } label: {
                        Text("Synchroniser maintenant").wLabel(13, color: Theme.accentBlue)
                    }.buttonStyle(.plain).disabled(!strap.state.isConnected)
                }
                DataQualityCard()
                CardBox(title: "Arrière-plan") {
                    Toggle(isOn: Binding(get: { app.settings.backgroundSync }, set: { app.settings.backgroundSync = $0 })) {
                        Text("Synchronisation périodique").font(WFont.text(15, weight: .medium)).foregroundColor(.white)
                    }
                    Toggle(isOn: Binding(get: { app.settings.continuousHR }, set: {
                        app.settings.continuousHR = $0
                        strap.setBackgroundLive($0)
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fréquence cardiaque en continu").font(WFont.text(15, weight: .medium)).foregroundColor(.white)
                            Text("Garde le flux en direct même app fermée (consomme plus de batterie du bracelet).")
                                .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
                        }
                    }
                }
                .tint(Theme.recoveryGreen)
                CardBox(title: "Actions") {
                    Button { strap.buzz() } label: { Label("Faire vibrer le bracelet", systemImage: "waveform") }
                        .disabled(!strap.state.isConnected)
                    Divider().overlay(Theme.separator)
                    NavigationLink { BluetoothLogView() } label: { Label("Journal Bluetooth", systemImage: "list.bullet.rectangle") }
                    Divider().overlay(Theme.separator)
                    Button(role: .destructive) { confirmForget = true } label: { Label("Oublier ce bracelet", systemImage: "trash") }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
            Text("Woop se connecte directement au bracelet en Bluetooth. Aucune donnée ne quitte ton iPhone, aucun compte n'est nécessaire.")
                .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
        }
        .confirmationDialog("Oublier ce bracelet ?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Oublier", role: .destructive) { strap.forget() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes données déjà synchronisées sont conservées.")
        }
    }

    private var statusCard: some View {
        CardBox {
            HStack(spacing: 16) {
                StrapGlyph(connected: strap.state.isConnected, charging: strap.charging).scaleEffect(1.6).frame(width: 40, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(strap.strapName ?? strap.model ?? "WHOOP").font(WFont.text(18, weight: .semibold)).foregroundColor(.white)
                    Text(strap.state.label).font(WFont.text(13, weight: .medium))
                        .foregroundColor(strap.state.isConnected ? Theme.recoveryGreen : Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(strap.battery.map { "\(Int($0.rounded())) %" } ?? "—").font(WFont.number(28, weight: .bold)).foregroundColor(.white)
                    Text(strap.charging ? "En charge" : "Batterie").font(WFont.text(11)).foregroundColor(Theme.textSecondary)
                }
            }
            if let hr = live.bpm {
                Divider().overlay(Theme.separator)
                HStack {
                    Image(systemName: "heart.fill").foregroundColor(Theme.recoveryRed)
                    Text("Fréquence cardiaque en direct").font(WFont.text(14)).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(hr)").font(WFont.number(26, weight: .bold)).foregroundColor(.white)
                    Text("bpm").font(WFont.text(11)).foregroundColor(Theme.textSecondary)
                }
            }
            if strap.model != nil || strap.firmware != nil {
                Divider().overlay(Theme.separator)
                row("Modèle", strap.model ?? "—")
                row("Numéro de série", strap.serial ?? "—")
                row("Firmware", strap.firmware ?? "—")
                if let w = strap.wristOn { row("Porté", w ? "Oui" : "Non") }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(WFont.text(14)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(v).font(WFont.text(14, weight: .semibold)).foregroundColor(.white)
        }
    }
}

/// Scan + connect, with the WHOOP 5.0 pairing instructions.
struct PairingCard: View {
    @EnvironmentObject var strap: StrapManager

    var body: some View {
        CardBox(title: "Connecter mon WHOOP") {
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Garde ton bracelet près de l'iPhone.")
                step(2, "Si l'app WHOOP officielle est sur cet iPhone, Woop peut partager la connexion. En cas de refus, ferme-la complètement.")
                step(3, "Pas de bracelet dans la liste ? Tape plusieurs fois sur le capteur jusqu'à ce que les LED clignotent en bleu (mode appairage).")
                step(4, "Accepte la demande d'appairage Bluetooth si iOS l'affiche.")
            }
            if let err = strap.lastError {
                Text(err).font(WFont.text(13)).foregroundColor(Theme.alarmOrange)
            }
            HStack {
                Button {
                    if strap.state == .scanning { strap.stopScan() } else { strap.startScan() }
                } label: {
                    HStack {
                        if strap.state == .scanning { ProgressView().tint(.black) }
                        Text(strap.state == .scanning ? "Arrêter la recherche" : "Rechercher mon bracelet").wLabel(12.5, color: .black)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            ForEach(strap.discovered) { d in
                Button { strap.connect(to: d.id) } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundColor(Theme.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(WFont.text(16, weight: .semibold)).foregroundColor(.white)
                            Text(d.generation?.label ?? "WHOOP").font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        if d.rssi != 0 { Text("\(d.rssi) dBm").font(WFont.text(12)).foregroundColor(Theme.textTertiary) }
                        Text("Connecter").wLabel(11, color: Theme.accentBlue)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardInner.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
            if strap.state == .bluetoothOff {
                Text("Active le Bluetooth dans le Centre de contrôle.").font(WFont.text(13)).foregroundColor(Theme.alarmOrange)
            } else if strap.state == .unauthorized {
                Text("Autorise Woop à utiliser le Bluetooth dans Réglages › Woop.").font(WFont.text(13)).foregroundColor(Theme.alarmOrange)
            }
        }
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(WFont.number(14, weight: .bold)).foregroundColor(.black)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.accentBlue))
            Text(t).font(WFont.text(13)).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BluetoothLogView: View {
    @ObservedObject private var logs = StrapManager.shared.logs

    var body: some View {
        DetailScaffold(title: "Journal Bluetooth") {
            if logs.lines.isEmpty {
                CardBox { Text("Aucun événement pour l'instant.").foregroundColor(Theme.textSecondary) }
            }
            ForEach(logs.lines.reversed()) { l in
                HStack(alignment: .top, spacing: 10) {
                    Text(Fmt.clock24(l.date)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textTertiary)
                    Text(l.text).font(WFont.text(12)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}


/// Firmware advisory: recent WHOOP 5.0 / MG firmware can withhold data from third-party apps,
/// and the official app installs firmware updates on its own.
struct FirmwareNotice: View {
    @EnvironmentObject var strap: StrapManager

    private var blockedNow: Bool {
        guard strap.state.isConnected, strap.emptySyncs >= 2 || strap.stalledSyncs >= 2 else { return false }
        return staleHours >= 3
    }

    /// Hours since the newest second received from the strap's history.
    private var staleHours: Double {
        guard let newest = Database.shared.newestHistoryTs() else { return 99 }
        return (Date().timeIntervalSince1970 - Double(newest)) / 3600
    }

    var body: some View {
        if blockedNow || strap.firmwareMayWithholdData {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.alarmOrange)
                    Text(blockedNow ? "Le bracelet est connecté mais ne renvoie aucune donnée"
                                    : "Firmware \(strap.firmware ?? "50.43") : accès aux données à surveiller")
                        .font(WFont.text(15, weight: .semibold)).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Depuis le firmware 50.43 (WHOOP 5.0 / MG), des bracelets ne livrent leur historique qu'après que l'app WHOOP officielle y a déposé son jeton d'abonnement signé (valable environ 45 jours). Woop ne peut pas créer ce jeton. Si la synchronisation ne ramène plus rien : ouvre l'app WHOOP officielle une fois, laisse-la se connecter au bracelet, puis reviens synchroniser ici.")
                    .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("L'app officielle met aussi le firmware à jour toute seule : c'est elle qui peut installer une version plus restrictive.")
                    .font(WFont.text(11.5)).foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.alarmOrange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.alarmOrange.opacity(0.6), lineWidth: 1))
        }
    }
}

/// How much of each recent day the strap actually delivered. Holes here are the first cause of
/// figures that differ from WHOOP's: a second that never reached the phone cannot be scored.
struct DataQualityCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @State private var rows: [DayCoverage] = []

    struct DayCoverage: Identifiable {
        var day: String
        var seconds: Int
        var id: String { day }
    }

    var body: some View {
        CardBox(title: "Qualité des données") {
            if rows.isEmpty {
                Text("Aucune donnée du bracelet pour l'instant.")
                    .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
            } else {
                ForEach(Array(rows.prefix(7))) { r in
                    HStack(spacing: 10) {
                        Text(Fmt.dayMonth(r.day)).font(WFont.text(13, weight: .medium)).foregroundColor(.white)
                            .frame(width: 74, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(color(r.seconds, day: r.day))
                                    .frame(width: max(r.seconds > 0 ? 5 : 0, g.size.width * share(r.seconds, day: r.day)))
                            }
                        }
                        .frame(height: 7)
                        Text(hours(r.seconds)).font(WFont.number(14, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
            Text("Heures de mesures reçues du bracelet par jour. Un jour bien en dessous de 24 h a des trous : les scores de ce jour-là sont calculés sur ce qui est arrivé. Les secondes vues seulement en direct (app ouverte) n'ont ni mouvement ni température.")
                .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let n = strap.lastSyncSeconds {
                Text("Dernier transfert : \(hours(n)) de données.")
                    .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
            }
        }
        .task(id: strap.lastSync) { await load() }
    }

    private func elapsed(_ day: String) -> Double {
        guard let start = DayKey.startUnix(day) else { return 86400 }
        return min(86400, max(60, Date().timeIntervalSince1970 - Double(start)))
    }

    private func share(_ seconds: Int, day: String) -> CGFloat {
        CGFloat(min(1, Double(seconds) / elapsed(day)))
    }

    private func color(_ seconds: Int, day: String) -> Color {
        let s = Double(seconds) / elapsed(day)
        return s >= 0.9 ? Theme.recoveryGreen : (s >= 0.6 ? Theme.recoveryYellow : Theme.recoveryRed)
    }

    private func hours(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }

    private func load() async {
        guard !app.settings.demoMode else { rows = []; return }
        let now = Int(Date().timeIntervalSince1970)
        let loaded: [DayCoverage] = await Task.detached(priority: .utility) {
            Database.shared.sampleSecondsByDay(from: now - 8 * 86400, to: now + 60) { DayKey.key(unix: $0) }
                .map { DayCoverage(day: $0.day, seconds: $0.seconds) }
        }.value
        rows = loaded
    }
}
