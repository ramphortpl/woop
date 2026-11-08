import SwiftUI

struct DashboardCustomizeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [DashboardMetric] = []
    @State private var toRemove: DashboardMetric?
    @State private var loaded = false

    private var available: [DashboardMetric] {
        DashboardMetric.allCases.filter { !selected.contains($0) }
            .sorted { $0.title.folding(options: .diacriticInsensitive, locale: .current) < $1.title.folding(options: .diacriticInsensitive, locale: .current) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: "Personnaliser le tableau de bord") { dismiss() }
                List {
                    Text("Mon tableau de bord")
                        .font(.system(size: 25, weight: .regular)).foregroundColor(.white)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 22, leading: 20, bottom: 14, trailing: 20))
                        .moveDisabled(true)

                    ForEach(selected) { m in
                        row(m, trailing: nil)
                            .contentShape(Rectangle())
                            .onTapGesture { toRemove = m }
                    }
                    .onMove { from, to in selected.move(fromOffsets: from, toOffset: to) }

                    HStack(spacing: 12) {
                        Text("Ajouter à mon tableau de bord").wLabel(13, weight: .bold, color: Theme.textSecondary, tracking: 1.6)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Rectangle().fill(Theme.textTertiary.opacity(0.5)).frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 34, leading: 20, bottom: 12, trailing: 20))
                    .moveDisabled(true)

                    ForEach(available) { m in
                        row(m, trailing: AnyView(
                            Button {
                                withAnimation { selected.append(m) }
                            } label: {
                                Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.borderless)
                        ))
                        .moveDisabled(true)
                    }

                    Color.clear.frame(height: 110)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            LinearGradient(stops: [.init(color: Theme.bgBottom.opacity(0), location: 0),
                                   .init(color: Theme.bgBottom.opacity(0.95), location: 0.55),
                                   .init(color: Theme.bgBottom, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)
            OutlineButton(title: "Enregistrer") {
                app.settings.dashboard = selected
                dismiss()
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 24)
        }
        .onAppear {
            if !loaded { selected = app.settings.dashboard; loaded = true }
        }
        .confirmationDialog(toRemove.map { "Retirer « \($0.title) » ?" } ?? "",
                            isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Retirer du tableau de bord", role: .destructive) {
                if let m = toRemove { withAnimation { selected.removeAll { $0 == m } } }
                toRemove = nil
            }
            Button("Annuler", role: .cancel) { toRemove = nil }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ m: DashboardMetric, trailing: AnyView?) -> some View {
        HStack(spacing: 16) {
            Image(systemName: m.icon).font(.system(size: 18)).foregroundColor(Theme.textSecondary).frame(width: 26)
            Text(m.title).wLabel(12.5, weight: .bold, tracking: 1.5).lineLimit(2).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            if m.isChart {
                Image(systemName: "chart.bar").font(.system(size: 22)).foregroundColor(Theme.textSecondary)
            }
            if let trailing { trailing }
        }
        .frame(minHeight: 50)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardGradient)
                .padding(.vertical, 5)
                .padding(.horizontal, 16)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 30, bottom: 6, trailing: 26))
    }
}
