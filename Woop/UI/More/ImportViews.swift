import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Importer depuis WHOOP": every way to bring the official export into Woop.
struct WhoopImportView: View {
    @EnvironmentObject var app: AppState
    @State private var picker: DocumentPicker.Mode?
    @State private var link = ""
    @FocusState private var linkFocused: Bool

    var body: some View {
        DetailScaffold(title: "Importer depuis WHOOP") {
            CardBox(title: "Pourquoi importer ?") {
                Text("Tes jours passés affichent exactement les scores WHOOP (récupération, effort, sommeil, entraînements). Et surtout, Woop apprend sur TES nuits WHOOP comment WHOOP calcule ta récupération, ton besoin de sommeil, ton effort et tes calories : les jours suivants, mesurés par le bracelet, sont notés avec ces mêmes réglages.")
                    .font(WFont.text(13)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let first = app.importedDays.keys.min(), let last = app.importedDays.keys.max() {
                    Label("\(app.importedDays.count) jours WHOOP importés (\(Fmt.longDate(first)) → \(Fmt.longDate(last)))",
                          systemImage: "checkmark.circle.fill")
                        .font(WFont.text(12, weight: .semibold)).foregroundColor(Theme.recoveryGreen)
                }
            }

            if let cal = app.calibration, !cal.isEmpty {
                CalibrationCard(cal: cal)
            }

            CardBox(title: "1 · Demande ton export") {
                step("Dans l'app WHOOP : profil › Paramètres › Exporter les données (« Data Export »). Le nom exact du menu peut varier selon la version.")
                step("WHOOP t'envoie un e-mail avec un lien vers un fichier .zip (« my_whoop_data_… »).")
            }

            CardBox(title: "2 · Ouvre-le dans Woop") {
                if app.importRunning {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(app.importStatusText ?? "Import en cours…").font(WFont.text(14, weight: .medium)).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let last = app.lastImportMessage {
                    Text(last).font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardInner.opacity(0.6)))
                }
                ImportOption(icon: "doc.zipper", title: "Choisir le fichier .zip",
                             detail: "Touche simplement le fichier dans la liste : l'import démarre tout de suite, sans bouton « Ouvrir ».") {
                    picker = .files
                }
                Divider().overlay(Theme.separator)
                ImportOption(icon: "folder", title: "Choisir le dossier décompressé",
                             detail: "Si Fichiers a déjà décompressé le .zip : entre dans le dossier « my_whoop_data… », puis touche « Ouvrir » en haut à droite.") {
                    picker = .folder
                }
                Divider().overlay(Theme.separator)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "link").font(.system(size: 18)).foregroundColor(Theme.accentBlue).frame(width: 26)
                        Text("Coller le lien de l'e-mail").font(WFont.text(16, weight: .semibold)).foregroundColor(.white)
                    }
                    Text("Dans l'e-mail WHOOP, appuie longuement sur le bouton de téléchargement › Copier le lien, puis colle-le ici.")
                        .font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("https://…", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($linkFocused)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardInner.opacity(0.6)))
                            .foregroundColor(.white)
                        Button {
                            if link.isEmpty, let s = UIPasteboard.general.string { link = s }
                            else {
                                linkFocused = false
                                app.importWhoop(link: link)
                            }
                        } label: {
                            Text(link.isEmpty ? "Coller" : "Importer").wLabel(12, color: .black)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(.plain)
                        .disabled(app.importRunning)
                    }
                }
            }

            CardBox(title: "Autres façons") {
                step("Depuis Mail, Safari ou Fichiers : touche le fichier .zip › Partager (carré avec une flèche) › Woop.")
                step("Ou dépose le .zip dans Fichiers › Sur mon iPhone › Woop : il est importé à la prochaine ouverture de Woop, puis rangé dans « Importés ».")
            }

            Text("Les exports en français et en anglais sont reconnus (fichiers .zip ou .csv, même réenregistrés par Numbers ou Excel). Le journal WHOOP est ignoré.")
                .font(WFont.text(11)).foregroundColor(Theme.textTertiary)
        }
        .sheet(item: $picker) { mode in
            DocumentPicker(mode: mode) { urls in
                picker = nil
                app.importWhoop(urls: urls)
            } onCancel: {
                picker = nil
            }
            .ignoresSafeArea()
        }
    }

    private func step(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.textTertiary).frame(width: 5, height: 5).padding(.top, 7)
            Text(t).font(WFont.text(13)).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImportOption: View {
    var icon: String
    var title: String
    var detail: String
    var action: () -> Void
    @EnvironmentObject var app: AppState

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(Theme.accentBlue).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(WFont.text(16, weight: .semibold)).foregroundColor(.white)
                    Text(detail).font(WFont.text(12)).foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(Theme.textTertiary).padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.importRunning)
    }
}

/// UIDocumentPickerViewController wrapper. `.files` copies the picked file (iCloud items are
/// downloaded first) and picks on a single tap; `.folder` selects a whole folder.
struct DocumentPicker: UIViewControllerRepresentable {
    enum Mode: String, Identifiable { case files, folder; var id: String { rawValue } }

    var mode: Mode
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc: UIDocumentPickerViewController
        switch mode {
        case .files:
            // `.data` covers a .zip or .csv whatever its exact type (and files saved without an
            // extension); a folder is never selectable here, so one tap picks the file.
            vc = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .commaSeparatedText, .data], asCopy: true)
        case .folder:
            vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        }
        vc.allowsMultipleSelection = false
        vc.shouldShowFileExtensions = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { parent = p }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}


/// What Woop learned from the wearer's WHOOP export ("Calibrage sur tes données WHOOP").
struct CalibrationCard: View {
    var cal: Calibration

    var body: some View {
        CardBox(title: "Calibrage sur tes données WHOOP") {
            Text(intro)
                .font(WFont.text(12)).foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            line("Récupération", on: cal.recovery != nil, detail: fit(cal.recoveryFit, unit: "pts", needs: "30 nuits avec VFC et récupération"))
            line("Score de sommeil", on: cal.perfWeights != nil, detail: fit(cal.perfFit, unit: "pts", needs: "21 nuits récentes"))
            line("Besoin de sommeil", on: cal.need != nil,
                 detail: needDetail)
            line("Dette de sommeil", on: cal.debtCarry != nil,
                 detail: cal.debtCarry.map { pct($0) + " du manque reporté" } ?? "valeur par défaut (55 %)")
            line("Régularité du sommeil", on: cal.consistency != nil, detail: fit(cal.consistencyFit, unit: "pts", needs: "21 nuits"))
            line("Échelle d'effort", on: cal.strainDenominator != nil, detail: fit(cal.strainFit, unit: "pt", needs: "8 entraînements d'effort ≥ 8"))
            line("Calories", on: cal.kcalActiveScale != nil,
                 detail: cal.kcalActiveScale.map { "×" + dec($0, 2) + " sur \(cal.kcalWorkouts) entraînements" }
                    ?? "il faut 8 entraînements avec FC et calories")
            line("Phases de sommeil", on: cal.stageShares != nil,
                 detail: cal.stageShares.map { stagesDetail($0) } ?? "il faut 7 nuits avec les phases")
            line("VFC et FC au repos", on: cal.hrvScale != nil || cal.rhrOffset != nil,
                 detail: overlapDetail)
        }
    }

    private var intro: String {
        var t = "\(cal.whoopNights) nuits WHOOP analysées"
        if cal.overlapNights > 0 { t += " · \(cal.overlapNights) nuits mesurées à la fois par WHOOP et par Woop" }
        return t + ". Chaque réglage n'est appliqué que s'il prédit mieux tes chiffres WHOOP que le réglage par défaut."
    }

    private var overlapDetail: String {
        var parts: [String] = []
        if let k = cal.hrvScale { parts.append("VFC ×" + dec(k, 2)) }
        if let o = cal.rhrOffset { parts.append("FC repos " + (o >= 0 ? "+" : "−") + dec(abs(o), 1)) }
        if !parts.isEmpty { return parts.joined(separator: " · ") + " (alignés sur WHOOP)" }
        return "il faut 5 nuits mesurées à la fois par WHOOP et par Woop : réimporte un export plus tard"
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    private func dec(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    private var needDetail: String {
        guard let n = cal.need else { return fit(cal.needFit, unit: "min", needs: "14 nuits consécutives") }
        var t = "base " + Fmt.hm(n.baseSec)
        if let f = cal.needFit { t += " · écart moyen \(Int(f.mae.rounded())) min" }
        return t
    }

    private func stagesDetail(_ s: Calibration.StageShares) -> String {
        "léger " + pct(s.light) + " · profond " + pct(s.deep) + " · paradoxal " + pct(s.rem) + " · éveil " + pct(s.awake)
    }

    private func fit(_ f: Calibration.Fit?, unit: String, needs: String) -> String {
        guard let f else { return "il faut \(needs)" }
        var out = "écart moyen " + dec(f.mae, 1) + " \(unit) sur \(f.n)"
        if let d = f.defaultMAE { out += " (défaut : " + dec(d, 1) + ")" }
        return out
    }

    private func line(_ title: String, on: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 15)).foregroundColor(on ? Theme.recoveryGreen : Theme.textMuted).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(WFont.text(14, weight: .semibold)).foregroundColor(.white)
                Text(on ? detail : "non appliqué — " + detail).font(WFont.text(11.5)).foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
