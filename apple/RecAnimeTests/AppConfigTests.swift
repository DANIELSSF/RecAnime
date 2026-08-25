import Foundation
import RecAnimeCore
import Testing

@Suite("App configuration")
struct AppConfigTests {
    @Test("Info.plist carries the API base URL")
    func infoPlistKeys() {
        let config = AppConfig.load(from: .main)
        #expect(config.apiBaseURL.scheme == "http" || config.apiBaseURL.scheme == "https")
        #expect(config.environment == .debug)
    }

    @Test("override wins over the compiled value")
    func override() {
        let config = AppConfig.load(from: .main, apiBaseURLOverride: "http://192.168.1.20:8080")
        #expect(config.apiBaseURL.host == "192.168.1.20")
    }
}
