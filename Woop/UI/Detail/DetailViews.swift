import SwiftUI

/// Header for pushed screens: thin back chevron and the day as an uppercase title.
struct DetailHeader: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String?
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(title).wLabel(12.3, tracking: 0.75).lineLimit(1).minimumScaleFactor(0.7)
                if let subtitle { Text(subtitle).font(WFont.text(12, weight: .medium)).foregroundColor(Theme.textSecondary) }
            }
            .padding(.horizontal, 70)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 21, weight: .light)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                Spacer()
                if let trailing { trailing }
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
    }
}

/// Generic scrolling detail scaffold (hides the tab bar, like WHOOP's detail screens).
struct DetailScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    var spacing: CGFloat = 16
    /// Scroll to this id once shown (CI screenshots).
    var scrollTo: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                DetailHeader(title: title, subtitle: subtitle)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: spacing, content: content)
                            .padding(.horizontal, Theme.side)
                            .padding(.top, 8)
                            .padding(.bottom, 110)
                    }
                    .onAppear {
                        guard let id = scrollTo else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }
}

/// Rounded card with an optional uppercase title.
struct CardBox<Content: View>: View {
    var title: String?
    var fade = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).wLabel(11.5) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(fade ? Theme.cardFade : Theme.cardGradient))
    }
}

/// Two-column grid of tiles.
struct TileGrid: View {
    var tiles: [StatTile]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in t }
        }
    }
}

/// Short explanation shown by the (i) buttons.
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var text: String

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                SheetHeader(title: title) { dismiss() }
                ScrollView {
                    Text(text).font(WFont.text(15.5)).foregroundColor(Color(hex: 0xD5D7DA)).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
