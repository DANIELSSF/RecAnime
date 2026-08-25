import Foundation

/// A MyAnimeList genre, theme or demographic. Ids are stable on MAL, so the Discover chips ship
/// with the app instead of spending a Jikan call (and a failure mode) on `/genres/anime`.
public struct Genre: Identifiable, Hashable, Sendable {
    public let id: Int
    /// MAL's English name; matches the strings the API returns in `AnimeDetail.genres`.
    public let name: String
    /// Label shown in the app.
    public let localizedName: String

    public init(id: Int, name: String, localizedName: String) {
        self.id = id
        self.name = name
        self.localizedName = localizedName
    }

    /// Genres first, then popular themes and demographics. Explicit genres are deliberately absent.
    public static let featured: [Genre] = [
        Genre(id: 1, name: "Action", localizedName: "Acción"),
        Genre(id: 2, name: "Adventure", localizedName: "Aventura"),
        Genre(id: 4, name: "Comedy", localizedName: "Comedia"),
        Genre(id: 8, name: "Drama", localizedName: "Drama"),
        Genre(id: 10, name: "Fantasy", localizedName: "Fantasía"),
        Genre(id: 22, name: "Romance", localizedName: "Romance"),
        Genre(id: 24, name: "Sci-Fi", localizedName: "Ciencia ficción"),
        Genre(id: 7, name: "Mystery", localizedName: "Misterio"),
        Genre(id: 41, name: "Suspense", localizedName: "Suspenso"),
        Genre(id: 14, name: "Horror", localizedName: "Terror"),
        Genre(id: 37, name: "Supernatural", localizedName: "Sobrenatural"),
        Genre(id: 36, name: "Slice of Life", localizedName: "Vida cotidiana"),
        Genre(id: 30, name: "Sports", localizedName: "Deportes"),
        Genre(id: 62, name: "Isekai", localizedName: "Isekai"),
        Genre(id: 18, name: "Mecha", localizedName: "Mecha"),
        Genre(id: 40, name: "Psychological", localizedName: "Psicológico"),
        Genre(id: 23, name: "School", localizedName: "Escolar"),
        Genre(id: 13, name: "Historical", localizedName: "Histórico"),
        Genre(id: 38, name: "Military", localizedName: "Militar"),
        Genre(id: 19, name: "Music", localizedName: "Música"),
        Genre(id: 47, name: "Gourmet", localizedName: "Gastronomía"),
        Genre(id: 46, name: "Award Winning", localizedName: "Premiados"),
        Genre(id: 27, name: "Shounen", localizedName: "Shounen"),
        Genre(id: 42, name: "Seinen", localizedName: "Seinen"),
        Genre(id: 25, name: "Shoujo", localizedName: "Shoujo"),
        Genre(id: 43, name: "Josei", localizedName: "Josei"),
    ]
}

/// Filter-only `GET /v1/search` (no text query): what the Discover tab asks for.
public struct BrowseQuery: Hashable, Sendable {
    public var genres: [Int]
    /// `score`, `members`, `popularity`, `start_date`, … (Jikan `order_by`).
    public var orderBy: String?
    /// `asc` or `desc`.
    public var sort: String?
    /// `airing`, `complete` or `upcoming`.
    public var status: String?
    public var type: String?
    public var minScore: Double?

    public init(genres: [Int] = [], orderBy: String? = nil, sort: String? = "desc", status: String? = nil, type: String? = nil, minScore: Double? = nil) {
        self.genres = genres
        self.orderBy = orderBy
        self.sort = sort
        self.status = status
        self.type = type
        self.minScore = minScore
    }
}
