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
                Text("Tes jours passés affichent exactement les scores WHOOP (récupération, effort, sommeil, entraînements) et tes moyennes de référence sont calibrées tout de suite, sans attendre 4 nuits.")
                    .font(.system(size: 13)).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let first = app.importedDays.keys.min(), let last = app.importedDays.keys.max() {
                    Label("\(app.importedDays.count) jours WHOOP importés (\(Fmt.longDate(first)) → \(Fmt.longDate(last)))",
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.recoveryGreen)
                }
            }

            CardBox(title: "1 · Demande ton export") {
                step("Dans l'app WHOOP : profil › Paramètres › Exporter les données (« Data Export »). Le nom exact du menu peut varier selon la version.")
                step("WHOOP t'envoie un e-mail avec un lien vers un fichier .zip (« my_whoop_data_… »).")
            }

            CardBox(title: "2 · Ouvre-le dans Woop") {
                if app.importRunning {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(app.importStatusText ?? "Import en cours…").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let last = app.lastImportMessage {
                    Text(last).font(.system(size: 12)).foregroundColor(Theme.textSecondary)
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
                        Text("Coller le lien de l'e-mail").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    }
                    Text("Dans l'e-mail WHOOP, appuie longuement sur le bouton de téléchargement › Copier le lien, puis colle-le ici.")
                        .font(.system(size: 12)).foregroundColor(Theme.textTertiary)
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
                            Text(link.isEmpty ? "Coller" : "Importer").wLabel(12, color: .black, tracking: 0.8)
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
                .font(.system(size: 11)).foregroundColor(Theme.textTertiary)
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
            Text(t).font(.system(size: 13)).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Text(detail).font(.system(size: 12)).foregroundColor(Theme.textTertiary)
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
