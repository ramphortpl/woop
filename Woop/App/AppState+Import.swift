import Foundation

extension AppState {
    struct ImportSummary {
        var days: Int
        var workouts: Int
        var files: Int
    }

    /// Import the official WHOOP data export: the .zip from WHOOP, individual CSV files, or an
    /// unzipped folder. Past days then show WHOOP's own scores and seed the personal baselines.
    func importWhoopExport(urls: [URL]) -> ImportSummary {
        var texts: [String] = []
        var files = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            collectCSV(url, into: &texts, files: &files, depth: 0)
        }
        let r = WhoopExport.importTexts(texts)
        var days = r.days
        for a in r.activities {
            if let i = days.firstIndex(where: { d in
                guard let s = d.cycleStart else { return false }
                return a.start >= s && a.start < (d.cycleEnd ?? s + 30 * 3600)
            }) {
                days[i].activities.append(a)
            } else if let i = days.firstIndex(where: { $0.date == DayKey.key(unix: a.start) }) {
                days[i].activities.append(a)
            }
        }
        Database.shared.saveImportedDays(days)
        for a in r.activities { Database.shared.saveActivity(a) }
        loadStored()
        recompute(daysBack: nil)
        return ImportSummary(days: days.count, workouts: r.activities.count, files: files)
    }

    private func collectCSV(_ url: URL, into texts: inout [String], files: inout Int, depth: Int) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            guard depth < 3 else { return }
            let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for item in items { collectCSV(item, into: &texts, files: &files, depth: depth + 1) }
            return
        }
        guard let data = try? Data(contentsOf: url) else { return }
        switch url.pathExtension.lowercased() {
        case "zip":
            for e in ZipReader.entries(data) where e.name.lowercased().hasSuffix(".csv") {
                if let t = String(data: e.data, encoding: .utf8) ?? String(data: e.data, encoding: .isoLatin1) {
                    texts.append(t)
                    files += 1
                }
            }
        case "csv", "txt":
            if let t = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                texts.append(t)
                files += 1
            }
        default:
            break
        }
    }
}
