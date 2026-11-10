import Foundation

/// Result of an import, shown as an alert wherever the user is.
struct ImportOutcome: Identifiable, Equatable {
    let id = UUID()
    var success: Bool
    var title: String
    var message: String
}

extension AppState {
    // MARK: Entry points

    /// Files or folders picked in Files, opened with "Partager › Woop", or dropped in Woop's
    /// Documents folder: the WHOOP .zip, CSV files, or an unzipped folder.
    func importWhoop(urls: [URL], cleanup: ImportCleanup = .keep) {
        guard !urls.isEmpty, !importRunning else { return }
        importRunning = true
        importStatusText = "Lecture de l'export WHOOP…"
        let label = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) fichiers"
        DispatchQueue.global(qos: .userInitiated).async {
            let read = Self.readFiles(urls)
            Self.cleanUp(urls, cleanup)
            Task { @MainActor in self.process(read.files, readErrors: read.errors, label: label) }
        }
    }

    /// The download link from WHOOP's e-mail, pasted in the app.
    func importWhoop(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importRunning else { return }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            importOutcome = ImportOutcome(success: false, title: "Lien invalide",
                                          message: "Colle le lien complet du bouton de téléchargement de l'e-mail WHOOP (il commence par https://).")
            return
        }
        importRunning = true
        importStatusText = "Téléchargement de l'export…"
        var req = URLRequest(url: url, timeoutInterval: 180)
        req.setValue("Woop", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: req) { tmp, response, error in
            var files: [ZipArchive.File] = []
            var errors: [String] = []
            if let error {
                errors.append(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                errors.append("le serveur a répondu \(http.statusCode) (lien expiré ?)")
            } else if let tmp, let data = try? Data(contentsOf: tmp) {
                let name = response?.suggestedFilename ?? url.lastPathComponent
                let bytes = [UInt8](data)
                let head = String(decoding: bytes.prefix(512), as: UTF8.self).lowercased()
                if !ZipArchive.isZip(bytes) && (head.contains("<html") || head.contains("<!doctype")) {
                    errors.append("ce lien ouvre une page web, pas le fichier. Ouvre-le dans Safari, télécharge le .zip, puis Partager › Woop.")
                } else {
                    files.append(ZipArchive.File(name: name, bytes: bytes))
                }
            } else {
                errors.append("fichier téléchargé illisible")
            }
            Task { @MainActor in self.process(files, readErrors: errors, label: "le lien") }
        }.resume()
    }

    /// Called by "Ouvrir avec Woop" / "Partager › Woop" (onOpenURL).
    func handleOpenedFile(_ url: URL) {
        guard url.isFileURL else { return }
        let inbox = url.path.contains("/Documents/Inbox/")
        importWhoop(urls: [url], cleanup: inbox ? .delete : .keep)
    }

    /// Exports dropped in Fichiers › Sur mon iPhone › Woop are imported, then moved to "Importés".
    func importDropFolderIfNeeded() {
        guard !importRunning, !settings.demoMode else { return }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        var found: [URL] = []
        let items = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for item in items where item.lastPathComponent != Self.importedFolderName {
            if item.lastPathComponent == "Inbox" {
                found += (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                continue
            }
            let ext = item.pathExtension.lowercased()
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir || ["zip", "csv"].contains(ext) { found.append(item) }
        }
        guard !found.isEmpty else { return }
        importWhoop(urls: found, cleanup: .moveToImported)
    }

    /// Makes "Woop" appear in Fichiers › Sur mon iPhone (an empty Documents folder may not show).
    nonisolated static func prepareDropFolder() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? fm.createDirectory(at: docs.appendingPathComponent(importedFolderName, isDirectory: true), withIntermediateDirectories: true)
    }

    enum ImportCleanup: Sendable { case keep, delete, moveToImported }

    nonisolated static let importedFolderName = "Importés"

    // MARK: Pipeline

    private func process(_ files: [ZipArchive.File], readErrors: [String], label: String) {
        importStatusText = "Analyse des données WHOOP…"
        let demo = settings.demoMode
        DispatchQueue.global(qos: .userInitiated).async {
            let collected = WhoopExport.collect(files)
            let result = WhoopExport.importFiles(collected.texts)
            if !demo, !result.days.isEmpty || !result.activities.isEmpty {
                Database.shared.saveImportedDays(result.days)
                for a in result.activities { Database.shared.saveActivity(a) }
            }
            let outcome = Self.outcome(result, collected: collected, readErrors: readErrors, label: label, demo: demo)
            Task { @MainActor in
                self.importRunning = false
                self.importStatusText = nil
                if outcome.success && !demo {
                    self.loadStored()
                    // Learn the wearer's own WHOOP mappings from the export, then rescore.
                    self.refitCalibration()
                }
                self.lastImportMessage = outcome.title + " — " + outcome.message
                self.importOutcome = outcome
            }
        }
    }

    nonisolated static func outcome(_ r: WhoopExport.Result, collected: WhoopExport.Collected, readErrors: [String],
                                    label: String, demo: Bool) -> ImportOutcome {
        let errors = (readErrors + collected.errors).prefix(3).joined(separator: "\n")
        if r.days.isEmpty && r.activities.isEmpty {
            var msg: String
            if collected.texts.isEmpty {
                msg = "Aucun fichier CSV trouvé dans « \(label) ». Choisis le fichier .zip envoyé par WHOOP (il contient physiological_cycles.csv, sleeps.csv et workouts.csv)."
            } else {
                let names = collected.texts.map(\.name).prefix(6).joined(separator: ", ")
                msg = "Fichiers lus : \(names). Aucun ne correspond à l'export WHOOP (physiological_cycles.csv, sleeps.csv, workouts.csv)."
            }
            if !errors.isEmpty { msg += "\n\nDétail : \(errors)" }
            return ImportOutcome(success: false, title: "Import impossible", message: msg)
        }
        if demo {
            return ImportOutcome(success: false, title: "Mode démo actif",
                                 message: "Désactive le mode démo (Plus › Mode démo) puis importe à nouveau : les données de démo ne sont jamais mélangées aux tiennes.")
        }
        var msg = "\(r.days.count) jour\(r.days.count > 1 ? "s" : "")"
        if let a = r.firstDay, let b = r.lastDay, a != b { msg += " (du \(longDay(a)) au \(longDay(b)))" }
        msg += " et \(r.activities.count) entraînement\(r.activities.count > 1 ? "s" : "") importés."
        let read = r.files.filter { $0.kind != nil && $0.kind != .journal }.map { $0.name }
        if !read.isEmpty { msg += "\nFichiers : \(read.joined(separator: ", "))." }
        msg += "\nTes jours passés affichent maintenant les scores WHOOP."
        return ImportOutcome(success: true, title: "Import WHOOP terminé", message: msg)
    }

    nonisolated private static func longDay(_ key: String) -> String {
        guard let t = DayKey.startUnix(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
    }

    // MARK: File access

    /// Read picked files/folders (security-scoped, iCloud items downloaded through file
    /// coordination). Folders are walked a few levels deep.
    nonisolated static func readFiles(_ urls: [URL]) -> (files: [ZipArchive.File], errors: [String]) {
        var files: [ZipArchive.File] = []
        var errors: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            gather(url, prefix: "", depth: 0, files: &files, errors: &errors)
        }
        return (files, errors)
    }

    nonisolated private static func gather(_ url: URL, prefix: String, depth: Int, files: inout [ZipArchive.File], errors: inout [String]) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            guard depth < 4 else { return }
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
            for item in items {
                var child = item
                let name = item.lastPathComponent
                // iCloud placeholder (".name.csv.icloud"): ask for the real file.
                if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                    child = item.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
                    try? fm.startDownloadingUbiquitousItem(at: child)
                } else if name.hasPrefix(".") {
                    continue
                }
                gather(child, prefix: prefix + url.lastPathComponent + "/", depth: depth + 1, files: &files, errors: &errors)
            }
            return
        }
        var coordError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do {
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 400 << 20 { throw CocoaError(.fileReadTooLarge) }
                data = try Data(contentsOf: u, options: .mappedIfSafe)
            } catch {
                readError = error
            }
        }
        if let data {
            files.append(ZipArchive.File(name: prefix + url.lastPathComponent, bytes: [UInt8](data)))
        } else {
            let why = readError?.localizedDescription ?? coordError?.localizedDescription ?? "lecture impossible"
            errors.append("\(url.lastPathComponent) : \(why)")
        }
    }

    nonisolated private static func cleanUp(_ urls: [URL], _ mode: ImportCleanup) {
        let fm = FileManager.default
        switch mode {
        case .keep:
            return
        case .delete:
            for u in urls { try? fm.removeItem(at: u) }
        case .moveToImported:
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let dest = docs.appendingPathComponent(importedFolderName, isDirectory: true)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for u in urls {
                if u.path.contains("/Documents/Inbox/") { try? fm.removeItem(at: u); continue }
                var target = dest.appendingPathComponent(u.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    let base = u.deletingPathExtension().lastPathComponent
                    let ext = u.pathExtension
                    target = dest.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                    n += 1
                }
                try? fm.moveItem(at: u, to: target)
            }
        }
    }
}
