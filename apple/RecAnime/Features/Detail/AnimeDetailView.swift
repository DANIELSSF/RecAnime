import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Anime page: hero, glass action cluster, franchise chain, synopsis and facts.
struct AnimeDetailView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    let malID: Int
    let api: any RecAnimeAPI
    @State private var detail: AnimeDetail?
    @State private var error: APIError?
    @State private var meta: Meta?
    @State private var showsNextSeasonDialog = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else if let seed = deps.summaries[malID], error == nil {
                // Instant paint during the zoom transition; the full record replaces it when loaded.
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    DetailHero(imageURL: seed.imageLargeURL, fallbackURL: seed.imageURL)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(seed.title).font(.title.bold())
                        if let english = seed.titleEnglish, english != seed.title {
                            Text(english).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xl)
                }
            } else if let error {
                EmptyStateView(
                    title: "No se pudo cargar",
                    message: LocalizedStringKey(error.userMessage),
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Reintentar"
                ) { Task { await load() } }
                    .padding(.top, 120)
            } else {
                ProgressView().padding(.top, 160)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(detail?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Más", systemImage: "ellipsis") {
                        if let url = URL(string: detail.malUrl) {
                            ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
                        }
                        if let url = URL(string: detail.malUrl) {
                            Link(destination: url) { Label("Ver en MyAnimeList", systemImage: "safari") }
                        }
                        if let trailer = detail.trailerUrl.flatMap(URL.init(string:)) {
                            Link(destination: trailer) { Label(
                                "Tráiler",
                                systemImage: "play.rectangle"
                            ) }
                        }
                    }
                }
            }
        }
        .task(id: malID) { await load() }
        .alert("No se pudo guardar", isPresented: Binding(get: { actionError != nil }, set: {
            if !$0 {
                actionError = nil
            }
        })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    // MARK: Sections

    @ViewBuilder
    private func content(_ detail: AnimeDetail) -> some View {
        let entry = library.items[detail.malId]
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            DetailHero(imageURL: detail.imageLargeURL, fallbackURL: deps.summaries[detail.malId]?.imageURL ?? detail.imageURL)
            titleBlock(detail)
            DetailActionCluster(detail: detail, entry: entry, onFinishedSeason: { showsNextSeasonDialog = true }, report: { actionError = $0 })
                .padding(.horizontal, Theme.Spacing.l)
            if let franchise = detail.franchise, FranchiseNavigator.hasChain(franchise) {
                FranchiseChainSection(malID: detail.malId, franchise: franchise)
            }
            if let synopsis = detail.synopsis, !synopsis.isEmpty {
                SynopsisView(text: synopsis).padding(.horizontal, Theme.Spacing.l)
            }
            DetailInfoGrid(detail: detail).padding(.horizontal, Theme.Spacing.l)
            if meta?.stale == true {
                Text("Datos guardados: MyAnimeList no respondió al actualizar.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, Theme.Spacing.l)
            }
        }
        .padding(.bottom, 120)
        .confirmationDialog("Temporada terminada", isPresented: $showsNextSeasonDialog, titleVisibility: .visible) {
            if let next = detail.franchise.flatMap({ FranchiseNavigator.next(after: detail.malId, in: $0) }), let anime = next.anime {
                Button("Empezar \(next.title)") {
                    Task { _ = try? await library.setStatus(.watching, for: anime); router.open(anime: next.malId) }
                }
                Button("Añadir a Pendientes") { Task { _ = try? await library.setStatus(.pending, for: anime) } }
            }
            Button("Ahora no", role: .cancel) {}
        } message: {
            if let next = detail.franchise.flatMap({ FranchiseNavigator.next(after: detail.malId, in: $0) }) {
                Text("¿Empezar \(next.title)?")
            } else {
                Text("No hay una temporada siguiente registrada.")
            }
        }
    }

    private func titleBlock(_ detail: AnimeDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.title).font(.title.bold())
            let alt = [detail.titleEnglish, detail.titleJapanese].compactMap(\.self).filter { $0 != detail.title }
            if !alt.isEmpty {
                Text(alt.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let type = detail.type {
                    badge(type)
                }
                if let year = detail.year {
                    badge(String(year))
                }
                if let episodes = detail.episodes {
                    badge("\(episodes) ep")
                }
                StatusBadge(LocalizedStringKey(airingLabel(detail.airingStatus)), color: airingColor(detail.airingStatus))
                if detail.score != nil {
                    ScoreLabel(score: detail.score).padding(.horizontal, 8).frame(height: 20).background(
                        .quaternary,
                        in: Capsule()
                    )
                }
                if let rank = detail.rank {
                    badge("#\(rank)")
                }
            }
            .padding(.top, 2)
            if !detail.genres.isEmpty {
                WrapLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(detail.genres, id: \.self) { genre in
                        Text(genre).font(.caption.weight(.medium)).padding(.horizontal, 10).frame(height: 24)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Géneros: \(detail.genres.joined(separator: ", "))")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 8).frame(height: 20).background(.quaternary, in: Capsule())
    }

    private func airingLabel(_ status: AiringStatus) -> String {
        switch status {
        case .airing: "En emisión"
        case .finished: "Finalizado"
        case .upcoming: "Próximamente"
        case .unknown: "Sin datos"
        }
    }

    private func airingColor(_ status: AiringStatus) -> Color {
        switch status {
        case .airing: Theme.accent
        case .finished: Theme.statusWatched
        case .upcoming, .unknown: Theme.statusPending
        }
    }

    private func load() async {
        do {
            let response = try await api.anime(malID)
            detail = response.data
            meta = response.meta
            error = nil
            library.seed(response.data.summary)
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .network(code: -1)
        }
    }
}

/// Large poster whose mirrored blur fills the area behind the toolbar.
private struct DetailHero: View {
    let imageURL: URL?
    /// Smaller artwork the list already cached; shown while the large image downloads so the zoom stays continuous.
    var fallbackURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if let fallbackURL {
                    AsyncImage(url: fallbackURL) { fallback in
                        fallback.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Theme.heroGradient.opacity(0.4))
                    }
                } else {
                    Rectangle().fill(Theme.heroGradient.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 440)
            .clipped()
            .backgroundExtensionEffect()
            LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .init(x: 0.5, y: 0.45), endPoint: .bottom)
                .frame(height: 440)
        }
        .frame(height: 440)
        .accessibilityHidden(true)
    }
}

/// Status segmented control + favorite + episode stepper: the one custom GlassEffectContainer.
struct DetailActionCluster: View {
    @Environment(LibraryStore.self) private var library
    let detail: AnimeDetail
    let entry: RecAnimeCore.LibraryItem?
    let onFinishedSeason: () -> Void
    let report: (String) -> Void
    @Namespace private var namespace

    private var status: WatchStatus {
        entry?.entry.status ?? .unknown
    }

    private var favorite: Bool {
        entry?.entry.favorite ?? false
    }

    private var watched: Int {
        entry?.entry.episodesWatched ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            GlassEffectContainer(spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    HStack(spacing: 2) {
                        ForEach([WatchStatus.pending, .watching, .watched], id: \.self) { candidate in
                            Button {
                                run { _ = try await library.setStatus(candidate, for: detail.summary) }
                            } label: {
                                Text(candidate.spanish)
                                    .font(.footnote.weight(candidate == status ? .bold : .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .foregroundStyle(candidate == status ? .white : .secondary)
                                    .background(candidate == status ? Theme.accent : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("detail.status.\(candidate.rawValue)")
                            .accessibilityAddTraits(candidate == status ? .isSelected : [])
                        }
                    }
                    .padding(4)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("status", in: namespace)

                    Button {
                        run { _ = try await library.toggleFavorite(for: detail.summary) }
                    } label: {
                        Image(systemName: favorite ? "heart.fill" : "heart")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(favorite ? Theme.favorite : .primary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: favorite)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("favorite", in: namespace)
                    .accessibilityIdentifier("detail.favorite")
                    .sensoryFeedback(.selection, trigger: favorite)
                    .accessibilityLabel(favorite ? "Quitar de favoritos" : "Añadir a favoritos")
                }
                if status == .watching {
                    HStack {
                        Button { library.increment(for: detail.summary, by: -1) } label: {
                            Image(systemName: "minus").frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail.episode.minus")
                        .disabled(watched == 0)
                        .accessibilityLabel("Un episodio menos")
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("EPISODIO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("\(watched)").font(.headline.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                            if let total = detail.episodes {
                                Text("/ \(total)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer()
                        Button {
                            if let total = detail.episodes, watched + 1 >= total {
                                run { _ = try await library.setStatus(.watched, for: detail.summary); onFinishedSeason() }
                            } else {
                                library.increment(for: detail.summary)
                            }
                        } label: {
                            Image(systemName: "plus").frame(width: 36, height: 36).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail.episode.plus")
                        .sensoryFeedback(.increase, trigger: watched)
                        .accessibilityLabel("Marcar episodio visto")
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("stepper", in: namespace)
                    .glassEffectTransition(.matchedGeometry)
                }
            }
            if status == .watching {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressPill(watched: watched, total: detail.episodes)
                    HStack {
                        if let total = detail.episodes {
                            Text("Faltan \(max(total - watched, 0))").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Marcar temporada vista") {
                            run { _ = try await library.setStatus(.watched, for: detail.summary); onFinishedSeason() }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .animation(.snappy, value: status)
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await work() } catch let error as APIError { report(error.userMessage) } catch { report(error.localizedDescription) }
        }
    }
}

/// Horizontal chain of seasons/movies with the current position highlighted.
struct FranchiseChainSection: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    let malID: Int
    let franchise: Franchise

    /// Opens a chain entry, seeding the detail page when the anime is cached.
    private func open(_ entry: FranchiseEntry) {
        guard entry.malId != malID else { return }
        if let anime = entry.anime {
            deps.summaries.remember(anime)
        }
        router.open(anime: entry.malId, source: "franchise-\(malID)-\(entry.malId)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Temporadas") {
                if franchise.entries.count > 6 || !franchise.sideEntries.isEmpty || !franchise.complete {
                    NavigationLink("Ver cadena", value: Route.franchise(malID))
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(Array(franchise.entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            if entry.malId != malID {
                                open(entry)
                            }
                        } label: {
                            FranchiseCard(entry: entry, isCurrent: index == franchise.currentIndex, isNext: index == franchise.currentIndex + 1)
                        }
                        .buttonStyle(.plain)
                        .zoomSource("franchise-\(malID)-\(entry.malId)")
                        .disabled(!entry.resolved && entry.malId == malID)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct FranchiseCard: View {
    let entry: FranchiseEntry
    let isCurrent: Bool
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: entry.anime?.imageURL, width: 90, height: 135)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2)
                        }
                    }
                if isCurrent {
                    chip("Estás aquí", background: Theme.accent, foreground: .white)
                } else if isNext {
                    chip("Siguiente", background: Color(.tertiarySystemFill), foreground: .primary)
                }
                if entry.anime?.library?.status == .watched {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Theme.statusWatched, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(width: 90, height: 135)
            Text("T\(entry.position)" + (entry.anime?.year.map { " · \($0)" } ?? ""))
                .font(.caption.weight(.semibold))
            Text(entry.anime?.episodes.map { "\($0) ep" } ?? (entry.resolved ? "" : "Sin datos"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 90)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title)\(isCurrent ? ", estás aquí" : "")")
    }

    private func chip(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(foreground)
            .padding(.horizontal, 7).frame(height: 20).background(background, in: Capsule()).padding(6)
    }
}

/// Full-chain list for long franchises plus side stories.
struct FranchiseListView: View {
    @Environment(Router.self) private var router
    let malID: Int
    let api: any RecAnimeAPI
    @State private var franchise: Franchise?
    @State private var error: APIError?

    var body: some View {
        List {
            if let franchise {
                Section("Cadena principal") {
                    ForEach(franchise.entries) { entry in
                        Button { router.open(anime: entry.malId) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                PosterImage(url: entry.anime?.imageURL, width: 44, height: 66, cornerRadius: Theme.Radius.thumb)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("T\(entry.position) · \(entry.title)").font(.subheadline.weight(.semibold))
                                    if let anime = entry.anime {
                                        MetadataRow([anime.type, anime.year.map(String.init), anime.episodes.map { "\($0) ep" }])
                                    } else {
                                        Text("Sin datos en caché todavía").font(.footnote).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if let overlay = entry.anime?.library {
                                    StatusBadge(LocalizedStringKey(overlay.status.spanish), color: Theme.status(overlay.status.rawValue))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !franchise.sideEntries.isEmpty {
                    Section("Relacionados") {
                        ForEach(franchise.sideEntries) { side in
                            Button { router.open(anime: side.malId) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(side.name).font(.subheadline.weight(.semibold))
                                    Text(side.relation).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !franchise.complete {
                    Text("La cadena puede seguir: algunas entradas aún no se han descargado de MyAnimeList.")
                        .font(.footnote).foregroundStyle(.tertiary)
                }
            }
        }
        .overlay {
            if franchise == nil {
                if let error {
                    EmptyStateView(
                        title: "No se pudo cargar",
                        message: LocalizedStringKey(error.userMessage),
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "Reintentar"
                    ) { Task { await load() } }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Temporadas")
        .task { await load() }
    }

    private func load() async {
        do {
            franchise = try await api.franchise(malID, budget: 4)
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .network(code: -1)
        }
    }
}

private struct SynopsisView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.subheadline).lineLimit(expanded ? nil : 4)
            Button(expanded ? "Menos" : "Más") { withAnimation(.snappy) { expanded.toggle() } }
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct DetailInfoGrid: View {
    let detail: AnimeDetail

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
            alignment: .leading,
            spacing: Theme.Spacing.l
        ) {
            cell("Emisión", detail.airedString.isEmpty ? "—" : detail.airedString)
            cell("Horario", broadcastLabel)
            if !detail.studios.isEmpty {
                cell("Estudio", detail.studios.joined(separator: ", "))
            }
            if let source = detail.source {
                cell("Fuente", source)
            }
            if let duration = detail.duration {
                cell("Duración", duration)
            }
            if let rating = detail.rating {
                cell("Clasificación", rating)
            }
            if let popularity = detail.popularity {
                cell("Popularidad", "#\(popularity)")
            }
            if !detail.streaming.isEmpty {
                cell("Dónde ver", detail.streaming.map(\.name).joined(separator: ", "))
            }
        }
    }

    private var broadcastLabel: String {
        guard let broadcast = detail.broadcast, let day = broadcast.day, let time = broadcast.time else { return "Sin horario" }
        var label = "\(day) \(time) \(broadcast.timezone == "Asia/Tokyo" ? "JST" : (broadcast.timezone ?? ""))"
        if let tz = broadcast.timezone, let zone = TimeZone(identifier: tz), let local = localTime(day: day, time: time, zone: zone) {
            label += " · \(local) aquí"
        }
        return label
    }

    private func localTime(day: String, time: String, zone: TimeZone) -> String? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var comps = Calendar.current.dateComponents(in: zone, from: .now)
        comps.hour = parts[0]
        comps.minute = parts[1]
        comps.second = 0
        guard let date = Calendar.current.date(from: comps) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
    }
}
