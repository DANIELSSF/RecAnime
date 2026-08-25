import RecAnimeUI
import SwiftUI

/// Tab shell: the system tab bar, search tab and bottom accessory all render in Liquid Glass.
struct RootView: View {
    enum Tab: Hashable {
        case season, top, recommendations, library, search
    }

    @State private var selection: Tab = .season

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Temporada", systemImage: "calendar", value: Tab.season) {
                PlaceholderScreen(title: "Temporada", subtitle: "Verano 2026", systemImage: "calendar")
            }
            SwiftUI.Tab("Top", systemImage: "trophy", value: Tab.top) {
                PlaceholderScreen(title: "Top", subtitle: nil, systemImage: "trophy")
            }
            SwiftUI.Tab("Recomendados", systemImage: "sparkles", value: Tab.recommendations) {
                PlaceholderScreen(title: "Recomendados", subtitle: "Comunidad de MyAnimeList · en vivo", systemImage: "sparkles")
            }
            SwiftUI.Tab("Mi lista", systemImage: "bookmark", value: Tab.library) {
                PlaceholderScreen(title: "Mi lista", subtitle: nil, systemImage: "bookmark")
            }
            SwiftUI.Tab(value: Tab.search, role: .search) {
                PlaceholderScreen(title: "Buscar", subtitle: nil, systemImage: "magnifyingglass")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowWatchingBar()
        }
    }
}

/// Temporary screen used while the feature screens are being built.
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    ForEach(0 ..< 12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(.quaternary)
                            .frame(height: 120)
                            .overlay(alignment: .leading) {
                                Text("Sección \(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, Theme.Spacing.l)
                            }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .navigationTitle(title)
            .modifier(SubtitleModifier(subtitle: subtitle))
        }
    }
}

private struct SubtitleModifier: ViewModifier {
    let subtitle: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// "Viendo ahora" mini bar living in the tab bar's bottom accessory (like Music's mini player).
struct NowWatchingBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Theme.heroGradient)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                if placement != .inline {
                    Text("VIENDO AHORA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("Sousou no Frieren 2nd Season").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("· ep 7/24").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Button {
                // Wired to LibraryStore.increment in the library milestone.
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Marcar episodio visto")
        }
        .padding(.horizontal, Theme.Spacing.m)
    }
}

#Preview {
    RootView().tint(Theme.accent)
}
