import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var strap: StrapManager
    @State private var confirmForget = false

    var body: some View {
        DetailScaffold(title: "Mon bracelet", subtitle: strap.strapName ?? strap.model) {
            statusCard
            if strap.pairedID == nil || !strap.state.isConnected {
                PairingCard()
            }
            if strap.pairedID != nil {
                CardBox(title: "Synchronisation") {
                    row("Dernière synchronisation", Fmt.relative(strap.lastSync))
                    if strap.syncing {
                        HStack {
                            ProgressView().tint(.white)
                            Text("Transfert en cours… \(Fmt.int(Double(strap.syncedThisSession))) s de données")
                                .font(.system(size: 13)).foregroundColor(Theme.textSecondary)
                        }
                        if let n = strap.syncNewest {
                            Text("Données jusqu'au \(n.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
                        }
                    }
                    Button { strap.syncNow() } label: {
                        Text("Synchroniser maintenant").wLabel(13, color: Theme.accentBlue)
                    }.buttonStyle(.plain).disabled(!strap.state.isConnected)
                }
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
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
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
                    Text(strap.strapName ?? strap.model ?? "WHOOP").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    Text(strap.state.label).font(.system(size: 13, weight: .medium))
                        .foregroundColor(strap.state.isConnected ? Theme.recoveryGreen : Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(strap.battery.map { "\(Int($0.rounded())) %" } ?? "—").font(WFont.number(28, weight: .bold)).foregroundColor(.white)
                    Text(strap.charging ? "En charge" : "Batterie").font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                }
            }
            if let hr = strap.liveHR {
                Divider().overlay(Theme.separator)
                HStack {
                    Image(systemName: "heart.fill").foregroundColor(Theme.recoveryRed)
                    Text("Fréquence cardiaque en direct").font(.system(size: 14)).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(hr)").font(WFont.number(26, weight: .bold)).foregroundColor(.white)
                    Text("bpm").font(.system(size: 11)).foregroundColor(Theme.textSecondary)
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
            Text(k).font(.system(size: 14)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(v).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
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
                Text(err).font(.system(size: 13)).foregroundColor(Theme.alarmOrange)
            }
            HStack {
                Button {
                    if strap.state == .scanning { strap.stopScan() } else { strap.startScan() }
                } label: {
                    HStack {
                        if strap.state == .scanning { ProgressView().tint(.black) }
                        Text(strap.state == .scanning ? "Arrêter la recherche" : "Rechercher mon bracelet").wLabel(12.5, color: .black, tracking: 1)
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
                            Text(d.name).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            Text(d.generation?.label ?? "WHOOP").font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        if d.rssi != 0 { Text("\(d.rssi) dBm").font(.system(size: 12)).foregroundColor(Theme.textTertiary) }
                        Text("Connecter").wLabel(11, color: Theme.accentBlue, tracking: 1)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardInner.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
            if strap.state == .bluetoothOff {
                Text("Active le Bluetooth dans le Centre de contrôle.").font(.system(size: 13)).foregroundColor(Theme.alarmOrange)
            } else if strap.state == .unauthorized {
                Text("Autorise Woop à utiliser le Bluetooth dans Réglages › Woop.").font(.system(size: 13)).foregroundColor(Theme.alarmOrange)
            }
        }
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(WFont.number(14, weight: .bold)).foregroundColor(.black)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.accentBlue))
            Text(t).font(.system(size: 13)).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BluetoothLogView: View {
    @EnvironmentObject var strap: StrapManager

    var body: some View {
        DetailScaffold(title: "Journal Bluetooth") {
            if strap.log.isEmpty {
                CardBox { Text("Aucun événement pour l'instant.").foregroundColor(Theme.textSecondary) }
            }
            ForEach(strap.log.reversed()) { l in
                HStack(alignment: .top, spacing: 10) {
                    Text(Fmt.clock24(l.date)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textTertiary)
                    Text(l.text).font(.system(size: 12)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
