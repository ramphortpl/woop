import SwiftUI
import UIKit

/// UI helpers over `SportCatalog`: icons are resolved against the SF Symbols available on this
/// iOS version (newer symbols fall back to an older equivalent).
enum Sport {
    static func label(_ key: String) -> String { SportCatalog.label(key) }
    static func name(_ a: ActivityRecord) -> String { SportCatalog.displayName(a) }

    static func icon(_ key: String) -> String {
        resolve(SportCatalog.info(key)?.icons ?? [])
    }

    private static var cache: [String: String] = [:]

    static func resolve(_ candidates: [String]) -> String {
        let k = candidates.joined(separator: "|")
        if let c = cache[k] { return c }
        let r = (candidates + [SportCatalog.fallbackIcon, "heart"]).first { UIImage(systemName: $0) != nil } ?? "heart"
        cache[k] = r
        return r
    }

    /// Shown first when nothing was used yet.
    static let popular = ["course", "cyclisme", "musculation", "marche", "padel", "tennis", "football", "natation",
                          "yoga", "hiit", "randonnee", "crossfit"]
}

/// Recently used activities (most recent first).
enum SportRecents {
    private static let key = "woop.sports.recent"

    static var keys: [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { SportCatalog.info($0) != nil }
    }

    static func add(_ sport: String) {
        var k = keys.filter { $0 != sport }
        k.insert(sport, at: 0)
        UserDefaults.standard.set(Array(k.prefix(8)), forKey: key)
    }

    /// Recents completed with popular activities, `count` items.
    static func quickPicks(_ count: Int, including selected: String? = nil) -> [String] {
        var out: [String] = []
        for k in ([selected].compactMap { $0 } + keys + Sport.popular) where !out.contains(k) && SportCatalog.info(k) != nil {
            out.append(k)
            if out.count == count { break }
        }
        return out
    }
}

/// Searchable list of every activity, grouped by family ("Choisir une activité").
struct SportPickerView: View {
    var selected: String?
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let recents = SportRecents.keys.compactMap(SportCatalog.info)
                    if !recents.isEmpty {
                        Section { rows(recents) } header: { header("Récents") }
                    }
                    ForEach(SportCategory.allCases, id: \.self) { c in
                        Section { rows(SportCatalog.inCategory(c)) } header: { header(c.title) }
                    }
                } else {
                    let found = SportCatalog.search(query)
                    if found.isEmpty {
                        Text("Aucune activité ne correspond. Choisis « Activité » ou « Autre ».")
                            .font(WFont.text(14)).foregroundColor(Theme.textSecondary)
                            .listRowBackground(Theme.card)
                    } else {
                        rows(found)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher : padel, ski, boxe…")
            .navigationTitle("Choisir une activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ t: String) -> some View {
        Text(t).wLabel(11.5, color: Theme.textSecondary)
    }

    private func rows(_ list: [SportInfo]) -> some View {
        ForEach(list) { s in
            Button {
                SportRecents.add(s.key)
                onPick(s.key)
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: Sport.resolve(s.icons)).font(.system(size: 19))
                        .foregroundColor(.white).frame(width: 30)
                    Text(s.label).font(WFont.text(16, weight: .medium)).foregroundColor(.white)
                    Spacer()
                    if s.key == selected {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.recoveryGreen)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.card)
        }
    }
}

/// Current activity + quick picks + "Toutes les activités" (used when adding or starting one).
struct SportChooser: View {
    @Binding var sport: String
    var quickCount = 9
    @State private var showAll = false

    var body: some View {
        VStack(spacing: 12) {
            Button { showAll = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: Sport.icon(sport)).font(.system(size: 26)).foregroundColor(.black)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Sport.label(sport)).font(WFont.text(19, weight: .semibold)).foregroundColor(.white)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Text("Changer d'activité").wLabel(11, color: Theme.accentBlue)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(SportRecents.quickPicks(quickCount, including: nil), id: \.self) { k in
                    Button { sport = k } label: {
                        VStack(spacing: 6) {
                            Image(systemName: Sport.icon(k)).font(.system(size: 22))
                            Text(Sport.label(k)).font(WFont.text(11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundColor(sport == k ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 12).fill(sport == k ? Color.white : Theme.cardInner.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { showAll = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Toutes les activités (\(SportCatalog.all.count))").wLabel(12)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().stroke(Theme.textTertiary, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showAll) {
            SportPickerView(selected: sport) { sport = $0 }
        }
    }
}
