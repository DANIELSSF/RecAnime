import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
@testable import RecAnimeKitTesting
import Testing

private struct BridgeTokenProvider: TokenProvider {
    let inner: StaticTokenProvider
    func accessToken() async throws -> String {
        try await inner.accessToken()
    }

    func forceRefresh() async throws -> String {
        try await inner.forceRefresh()
    }
}

@Suite("APIClient", .serialized)
struct APIClientTests {
    let base = URL(string: "https://api.example.test")!

    func makeClient() -> (APIClient, StaticTokenProvider) {
        let tokens = StaticTokenProvider()
        let client = APIClient(baseURL: base, tokenProvider: BridgeTokenProvider(inner: tokens), session: MockURLProtocol.session())
        return (client, tokens)
    }

    @Test("decodes the envelope and sends the bearer token")
    func decodesEnvelope() async throws {
        let (client, _) = makeClient()
        MockURLProtocol.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
            #expect(request.url?.path == "/v1/me")
            return MockURLProtocol.json(
                200,
                #"{"data":{"id":"u1","email":"a@b.c","displayName":"A","avatarUrl":"","createdAt":"2026-08-24T10:00:00Z","settings":{"sfw":true,"timezone":"UTC"}}}"#,
                for: request
            )
        }
        let me: APIResponse<User> = try await client.send(.me)
        #expect(me.data.email == "a@b.c")
    }

    @Test("401 triggers exactly one refresh and a retry")
    func refreshOn401() async throws {
        let (client, tokens) = makeClient()
        MockURLProtocol.setHandler { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" {
                return MockURLProtocol.json(401, #"{"error":{"code":"unauthorized","message":"expired"}}"#, for: request)
            }
            return MockURLProtocol.json(200, #"{"data":{"sfw":false,"timezone":"UTC"}}"#, for: request)
        }
        let settings: APIResponse<Settings> = try await client.send(.updateSettings(SettingsPatch(sfw: false)))
        #expect(settings.data.sfw == false)
        #expect(tokens.refreshes == 1)

        MockURLProtocol.setHandler { request in MockURLProtocol.json(401, "{}", for: request) }
        await #expect(throws: APIError.unauthorized) {
            let _: APIResponse<User> = try await client.send(.me)
        }
    }

    @Test("server errors carry the API error code; 204 works for deletes")
    func serverErrorsAndNoContent() async throws {
        let (client, _) = makeClient()
        MockURLProtocol.setHandler { request in
            MockURLProtocol.json(400, #"{"error":{"code":"validation_error","message":"q too short","requestId":"r1"}}"#, for: request)
        }
        await #expect(throws: APIError.server(status: 400, code: "validation_error", message: "q too short")) {
            let _: APIResponse<[AnimeSummary]> = try await client.send(.search("ab"))
        }
        MockURLProtocol.setHandler { request in
            #expect(request.httpMethod == "DELETE")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await client.sendNoContent(.deleteLibrary(1))
    }

    @Test("query building drops empty values and encodes bodies")
    func endpoints() throws {
        let req = Endpoint.top(filter: nil, type: "tv", page: 2).request(baseURL: base)
        #expect(req.url?.absoluteString == "https://api.example.test/v1/top?type=tv&page=2")
        let first = Endpoint.seasonNow(page: 1).request(baseURL: base)
        #expect(first.url?.query == nil)
        let put = Endpoint.upsertLibrary(5, LibraryPatch(status: .watching, episodesWatched: 3)).request(baseURL: base)
        let body = try JSONSerialization.jsonObject(with: #require(put.httpBody)) as? [String: Any]
        #expect(body?["status"] as? String == "watching")
        #expect(body?["episodesWatched"] as? Int == 3)
        #expect(body?["favorite"] == nil)
        #expect(put.httpMethod == "PUT")
    }
}
