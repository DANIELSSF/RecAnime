import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKitTesting
import Testing

@Suite("Golden fixtures")
struct FixturesTests {
    @Test("every golden fixture is present and is valid JSON")
    func fixturesLoad() throws {
        for name in [
            "me",
            "anime_detail",
            "anime_franchise",
            "anime_episodes",
            "seasons_index",
            "season_now",
            "top",
            "search",
            "recommendations",
            "library_grouped",
            "library_item",
            "schedule",
            "error_not_found",
            "error_validation",
        ] {
            let data = try Fixtures.data(name)
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    @Test("identifiers derive deep links")
    func deepLink() {
        #expect(Identifiers.animeURL(malID: 52991).absoluteString == "recanime://anime/52991")
    }
}
