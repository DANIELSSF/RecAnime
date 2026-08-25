import Foundation

// JSON shapes returned by the Go API (services/api/internal/model/model.go). Field names are
// camelCase on both sides so no key strategy is needed. Enums decode leniently: unknown values map
// to `.unknown` instead of failing the whole response.

// MARK: - Enums

public enum WatchStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case pending
    case watching
    case watched
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WatchStatus(rawValue: raw) ?? .unknown
    }
}

public enum AiringStatus: String, Codable, Sendable, Hashable {
    case airing
    case finished
    case upcoming
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AiringStatus(rawValue: raw) ?? .unknown
    }
}

public enum CacheStatus: String, Codable, Sendable, Hashable {
    case hit = "HIT"
    case miss = "MISS"
    case stale = "STALE"
    case live = "LIVE"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CacheStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - Envelope

public struct Meta: Codable, Sendable, Hashable {
    public var cache: CacheStatus?
    public var fetchedAt: Date?
    public var stale: Bool
    public var upstreamError: String?

    public init(cache: CacheStatus? = nil, fetchedAt: Date? = nil, stale: Bool = false, upstreamError: String? = nil) {
        self.cache = cache
        self.fetchedAt = fetchedAt
        self.stale = stale
        self.upstreamError = upstreamError
    }
}

public struct Pagination: Codable, Sendable, Hashable {
    public var page: Int
    public var perPage: Int
    public var hasNextPage: Bool
    public var lastVisiblePage: Int
    public var total: Int

    public init(page: Int, perPage: Int, hasNextPage: Bool, lastVisiblePage: Int, total: Int) {
        self.page = page
        self.perPage = perPage
        self.hasNextPage = hasNextPage
        self.lastVisiblePage = lastVisiblePage
        self.total = total
    }
}

public struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    public var data: T
    public var meta: Meta?
    public var pagination: Pagination?
}

public struct APIErrorBody: Codable, Sendable, Hashable {
    public struct Detail: Codable, Sendable, Hashable {
        public var code: String
        public var message: String
        public var requestId: String?
    }

    public var error: Detail
}

// MARK: - Anime

public struct LibraryOverlay: Codable, Sendable, Hashable {
    public var status: WatchStatus
    public var favorite: Bool
    public var episodesWatched: Int
    public var updatedAt: Date

    public init(status: WatchStatus, favorite: Bool, episodesWatched: Int, updatedAt: Date) {
        self.status = status
        self.favorite = favorite
        self.episodesWatched = episodesWatched
        self.updatedAt = updatedAt
    }
}

public struct AnimeSummary: Codable, Sendable, Hashable, Identifiable {
    public var malId: Int
    public var title: String
    public var titleEnglish: String?
    public var imageUrl: String
    public var imageLargeUrl: String
    public var type: String?
    public var episodes: Int?
    public var status: String?
    public var airingStatus: AiringStatus
    public var airing: Bool
    public var score: Double?
    public var rank: Int?
    public var popularity: Int?
    public var members: Int?
    public var year: Int?
    public var season: String?
    public var rating: String?
    public var isAdult: Bool
    public var library: LibraryOverlay?

    public var id: Int {
        malId
    }

    public var imageURL: URL? {
        URL(string: imageUrl)
    }

    public var imageLargeURL: URL? {
        URL(string: imageLargeUrl.isEmpty ? imageUrl : imageLargeUrl)
    }

    public init(
        malId: Int,
        title: String,
        titleEnglish: String? = nil,
        imageUrl: String = "",
        imageLargeUrl: String = "",
        type: String? = nil,
        episodes: Int? = nil,
        status: String? = nil,
        airingStatus: AiringStatus = .unknown,
        airing: Bool = false,
        score: Double? = nil,
        rank: Int? = nil,
        popularity: Int? = nil,
        members: Int? = nil,
        year: Int? = nil,
        season: String? = nil,
        rating: String? = nil,
        isAdult: Bool = false,
        library: LibraryOverlay? = nil
    ) {
        self.malId = malId
        self.title = title
        self.titleEnglish = titleEnglish
        self.imageUrl = imageUrl
        self.imageLargeUrl = imageLargeUrl
        self.type = type
        self.episodes = episodes
        self.status = status
        self.airingStatus = airingStatus
        self.airing = airing
        self.score = score
        self.rank = rank
        self.popularity = popularity
        self.members = members
        self.year = year
        self.season = season
        self.rating = rating
        self.isAdult = isAdult
        self.library = library
    }
}

public struct Link: Codable, Sendable, Hashable {
    public var name: String
    public var url: String
}

public struct BroadcastInfo: Codable, Sendable, Hashable {
    public var day: String?
    public var time: String?
    public var timezone: String?
    public var string: String?

    public init(day: String? = nil, time: String? = nil, timezone: String? = nil, string: String? = nil) {
        self.day = day
        self.time = time
        self.timezone = timezone
        self.string = string
    }
}

public struct RelationEntry: Codable, Sendable, Hashable {
    public var malId: Int
    public var type: String
    public var name: String
}

public struct RelationGroup: Codable, Sendable, Hashable {
    public var relation: String
    public var entries: [RelationEntry]
}

public struct FranchiseEntry: Codable, Sendable, Hashable, Identifiable {
    public var malId: Int
    public var title: String
    public var position: Int
    public var resolved: Bool
    public var relationToPrevious: String?
    public var anime: AnimeSummary?

    public var id: Int {
        malId
    }
}

public struct SideEntry: Codable, Sendable, Hashable, Identifiable {
    public var relation: String
    public var malId: Int
    public var name: String

    public var id: Int {
        malId
    }
}

public struct Franchise: Codable, Sendable, Hashable {
    public var entries: [FranchiseEntry]
    public var requestedIndex: Int
    public var currentIndex: Int
    public var nextSeason: FranchiseEntry?
    public var complete: Bool
    public var sideEntries: [SideEntry]
}

/// Full anime page. The Go side embeds the summary, so its fields appear at the top level here too.
public struct AnimeDetail: Codable, Sendable, Hashable, Identifiable {
    public var malId: Int
    public var title: String
    public var titleEnglish: String?
    public var imageUrl: String
    public var imageLargeUrl: String
    public var type: String?
    public var episodes: Int?
    public var status: String?
    public var airingStatus: AiringStatus
    public var airing: Bool
    public var score: Double?
    public var rank: Int?
    public var popularity: Int?
    public var members: Int?
    public var year: Int?
    public var season: String?
    public var rating: String?
    public var isAdult: Bool
    public var library: LibraryOverlay?

    public var titleJapanese: String?
    public var synopsis: String?
    public var background: String?
    public var source: String?
    public var duration: String?
    public var scoredBy: Int?
    public var favorites: Int?
    public var airedFrom: Date?
    public var airedTo: Date?
    public var airedString: String
    public var broadcast: BroadcastInfo?
    public var trailerUrl: String?
    public var malUrl: String
    public var genres: [String]
    public var themes: [String]
    public var demographics: [String]
    public var studios: [String]
    public var producers: [String]
    public var streaming: [Link]
    public var external: [Link]
    public var relations: [RelationGroup]
    public var franchise: Franchise?

    public var id: Int {
        malId
    }

    public var imageURL: URL? {
        URL(string: imageUrl)
    }

    public var imageLargeURL: URL? {
        URL(string: imageLargeUrl.isEmpty ? imageUrl : imageLargeUrl)
    }

    /// Card representation of this detail (for lists that reuse detail data).
    public var summary: AnimeSummary {
        AnimeSummary(
            malId: malId,
            title: title,
            titleEnglish: titleEnglish,
            imageUrl: imageUrl,
            imageLargeUrl: imageLargeUrl,
            type: type,
            episodes: episodes,
            status: status,
            airingStatus: airingStatus,
            airing: airing,
            score: score,
            rank: rank,
            popularity: popularity,
            members: members,
            year: year,
            season: season,
            rating: rating,
            isAdult: isAdult,
            library: library
        )
    }
}

// MARK: - Library

public struct LibraryEntry: Codable, Sendable, Hashable {
    public var status: WatchStatus
    public var favorite: Bool
    public var episodesWatched: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(status: WatchStatus, favorite: Bool, episodesWatched: Int, createdAt: Date, updatedAt: Date) {
        self.status = status
        self.favorite = favorite
        self.episodesWatched = episodesWatched
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Progress: Codable, Sendable, Hashable {
    public var episodesTotal: Int?
    public var remaining: Int?

    public init(episodesTotal: Int? = nil, remaining: Int? = nil) {
        self.episodesTotal = episodesTotal
        self.remaining = remaining
    }
}

public struct LibraryItem: Codable, Sendable, Hashable, Identifiable {
    public var anime: AnimeSummary
    public var entry: LibraryEntry
    public var progress: Progress

    public var id: Int {
        anime.malId
    }

    public init(anime: AnimeSummary, entry: LibraryEntry, progress: Progress) {
        self.anime = anime
        self.entry = entry
        self.progress = progress
    }
}

public struct LibraryGroups: Codable, Sendable, Hashable {
    public var watching: [LibraryItem]
    public var pending: [LibraryItem]
    public var watched: [LibraryItem]
    public var favorites: [LibraryItem]

    public init(watching: [LibraryItem] = [], pending: [LibraryItem] = [], watched: [LibraryItem] = [], favorites: [LibraryItem] = []) {
        self.watching = watching
        self.pending = pending
        self.watched = watched
        self.favorites = favorites
    }

    public var all: [LibraryItem] {
        watching + pending + watched
    }
}

/// Body of `PUT /v1/me/library/{malId}`: nil fields are left untouched by the server.
public struct LibraryPatch: Codable, Sendable, Hashable {
    public var status: WatchStatus?
    public var favorite: Bool?
    public var episodesWatched: Int?

    public init(status: WatchStatus? = nil, favorite: Bool? = nil, episodesWatched: Int? = nil) {
        self.status = status
        self.favorite = favorite
        self.episodesWatched = episodesWatched
    }
}

/// Body of `POST /v1/me/library/{malId}/episodes`: exactly one of the fields.
public struct EpisodesAdjustment: Codable, Sendable, Hashable {
    public var episodesWatched: Int?
    public var delta: Int?

    public static func set(_ value: Int) -> EpisodesAdjustment {
        EpisodesAdjustment(episodesWatched: value, delta: nil)
    }

    public static func delta(_ value: Int) -> EpisodesAdjustment {
        EpisodesAdjustment(episodesWatched: nil, delta: value)
    }
}

// MARK: - Catalog

public struct Episode: Codable, Sendable, Hashable, Identifiable {
    public var number: Int
    public var title: String
    public var aired: Date?
    public var filler: Bool
    public var recap: Bool
    public var score: Double?
    public var url: String?

    public var id: Int {
        number
    }
}

public struct RecommendationEntry: Codable, Sendable, Hashable, Identifiable {
    public var malId: Int
    public var title: String
    public var imageUrl: String
    public var library: LibraryOverlay?

    public var id: Int {
        malId
    }

    public var imageURL: URL? {
        URL(string: imageUrl)
    }
}

public struct RecommendationUser: Codable, Sendable, Hashable {
    public var username: String
    public var url: String
}

public struct Recommendation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var entries: [RecommendationEntry]
    public var content: String
    public var date: Date?
    public var user: RecommendationUser
}

public struct AnimeRecommendation: Codable, Sendable, Hashable, Identifiable {
    public var anime: RecommendationEntry
    public var votes: Int

    public var id: Int {
        anime.malId
    }
}

public struct SeasonIndex: Codable, Sendable, Hashable, Identifiable {
    public var year: Int
    public var seasons: [String]

    public var id: Int {
        year
    }
}

// MARK: - Schedule

public struct LatestEpisode: Codable, Sendable, Hashable {
    public var number: Int
    public var airedAt: Date?
    public var source: String
}

public struct ScheduleItem: Codable, Sendable, Hashable, Identifiable {
    public var malId: Int
    public var title: String
    public var imageUrl: String
    public var broadcast: BroadcastInfo?
    public var nextAiringAt: Date?
    public var nextEpisodeNumber: Int?
    public var latestEpisode: LatestEpisode?
    public var episodesTotal: Int?
    public var episodesWatched: Int
    public var remaining: Int?
    public var status: String?
    public var airing: Bool
    public var reason: String?

    public var id: Int {
        malId
    }

    public init(
        malId: Int,
        title: String,
        imageUrl: String = "",
        broadcast: BroadcastInfo? = nil,
        nextAiringAt: Date? = nil,
        nextEpisodeNumber: Int? = nil,
        latestEpisode: LatestEpisode? = nil,
        episodesTotal: Int? = nil,
        episodesWatched: Int = 0,
        remaining: Int? = nil,
        status: String? = nil,
        airing: Bool = true,
        reason: String? = nil
    ) {
        self.malId = malId
        self.title = title
        self.imageUrl = imageUrl
        self.broadcast = broadcast
        self.nextAiringAt = nextAiringAt
        self.nextEpisodeNumber = nextEpisodeNumber
        self.latestEpisode = latestEpisode
        self.episodesTotal = episodesTotal
        self.episodesWatched = episodesWatched
        self.remaining = remaining
        self.status = status
        self.airing = airing
        self.reason = reason
    }
}

// MARK: - User

public struct Settings: Codable, Sendable, Hashable {
    public var sfw: Bool
    public var timezone: String

    public init(sfw: Bool, timezone: String) {
        self.sfw = sfw
        self.timezone = timezone
    }
}

public struct SettingsPatch: Codable, Sendable, Hashable {
    public var sfw: Bool?
    public var timezone: String?

    public init(sfw: Bool? = nil, timezone: String? = nil) {
        self.sfw = sfw
        self.timezone = timezone
    }
}

public struct User: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var email: String
    public var displayName: String
    public var avatarUrl: String
    public var createdAt: Date
    public var settings: Settings

    public var avatarURL: URL? {
        avatarUrl.isEmpty ? nil : URL(string: avatarUrl)
    }
}
