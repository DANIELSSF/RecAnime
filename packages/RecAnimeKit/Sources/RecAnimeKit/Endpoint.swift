import Foundation
import RecAnimeCore

/// One API route: method, path, query and optional JSON body.
public struct Endpoint: Sendable, Hashable {
    public enum Method: String, Sendable {
        case get = "GET", put = "PUT", post = "POST", patch = "PATCH", delete = "DELETE"
    }

    public var method: Method
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?

    public init(method: Method = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    /// Builds the request against `baseURL`; drops empty query values.
    public func request(baseURL: URL) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        )!
        let items = query.filter { !($0.value ?? "").isEmpty }
        components.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func json(_ value: some Encodable) -> Data {
        // Encoding request bodies of our own Codable types cannot fail in practice.
        (try? JSONEncoder.recanime.encode(value)) ?? Data("{}".utf8)
    }

    static func page(_ page: Int) -> URLQueryItem {
        URLQueryItem(name: "page", value: page > 1 ? String(page) : nil)
    }

    // MARK: Routes

    public static var me: Endpoint {
        Endpoint(path: "v1/me")
    }

    public static func updateSettings(_ patch: SettingsPatch) -> Endpoint {
        Endpoint(method: .patch, path: "v1/me/settings", body: json(patch))
    }

    public static func anime(_ id: Int) -> Endpoint {
        Endpoint(path: "v1/anime/\(id)")
    }

    public static func franchise(_ id: Int, budget: Int? = nil) -> Endpoint {
        Endpoint(path: "v1/anime/\(id)/franchise", query: [URLQueryItem(name: "budget", value: budget.map(String.init))])
    }

    public static func episodes(_ id: Int, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/anime/\(id)/episodes", query: [Self.page(page)])
    }

    public static func animeRecommendations(_ id: Int) -> Endpoint {
        Endpoint(path: "v1/anime/\(id)/recommendations")
    }

    public static var seasonsIndex: Endpoint {
        Endpoint(path: "v1/seasons")
    }

    public static func seasonNow(filter: String? = nil, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/seasons/now", query: [URLQueryItem(name: "filter", value: filter), Self.page(page)])
    }

    public static func seasonUpcoming(filter: String? = nil, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/seasons/upcoming", query: [URLQueryItem(name: "filter", value: filter), Self.page(page)])
    }

    public static func season(year: Int, season: String, filter: String? = nil, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/seasons/\(year)/\(season)", query: [URLQueryItem(name: "filter", value: filter), Self.page(page)])
    }

    public static func top(filter: String? = nil, type: String? = nil, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/top", query: [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "type", value: type), Self.page(page)])
    }

    public static func recommendations(page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/recommendations", query: [Self.page(page)])
    }

    public static func search(_ q: String, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/search", query: [URLQueryItem(name: "q", value: q), Self.page(page)])
    }

    public static func schedules(day: String, page: Int = 1) -> Endpoint {
        Endpoint(path: "v1/schedules", query: [URLQueryItem(name: "day", value: day), Self.page(page)])
    }

    public static var library: Endpoint {
        Endpoint(path: "v1/me/library")
    }

    public static func library(status: WatchStatus?, favorite: Bool?) -> Endpoint {
        Endpoint(path: "v1/me/library", query: [
            URLQueryItem(name: "status", value: status?.rawValue),
            URLQueryItem(name: "favorite", value: favorite.map { $0 ? "true" : "false" }),
        ])
    }

    public static func libraryItem(_ id: Int) -> Endpoint {
        Endpoint(path: "v1/me/library/\(id)")
    }

    public static func upsertLibrary(_ id: Int, _ patch: LibraryPatch) -> Endpoint {
        Endpoint(method: .put, path: "v1/me/library/\(id)", body: json(patch))
    }

    public static func adjustEpisodes(_ id: Int, _ adjustment: EpisodesAdjustment) -> Endpoint {
        Endpoint(method: .post, path: "v1/me/library/\(id)/episodes", body: json(adjustment))
    }

    public static func deleteLibrary(_ id: Int) -> Endpoint {
        Endpoint(method: .delete, path: "v1/me/library/\(id)")
    }

    public static func schedule(includeEpisodes: Bool = false) -> Endpoint {
        Endpoint(path: "v1/me/schedule", query: [URLQueryItem(name: "includeEpisodes", value: includeEpisodes ? "true" : nil)])
    }
}
