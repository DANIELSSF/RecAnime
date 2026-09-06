import Foundation
@testable import RecAnimeCore
import Testing

@Suite("AppConfig loading")
struct AppConfigTests {
    private func info(api: String = "", supabase: String = "", key: String = "", env: String = "release") -> [String: Any] {
        [
            "RAAPIBaseURL": api,
            "RASupabaseURL": supabase,
            "RASupabasePublishableKey": key,
            "RAEnvironment": env,
        ]
    }

    @Test("an empty API URL is not configured and falls back to localhost")
    func emptyURL() {
        let config = AppConfig.load(info: info())
        #expect(config.isAPIConfigured == false)
        #expect(config.apiBaseURL == URL(string: "http://localhost:8080"))
    }

    @Test("the placeholder Cloud Run host is not configured")
    func placeholderURL() {
        let config = AppConfig.load(info: info(api: "https://recanime-api.example.run.app"))
        #expect(config.isAPIConfigured == false)
    }

    @Test("a real https URL is configured")
    func realURL() {
        let config = AppConfig.load(info: info(api: "https://recanime-api-abcd-ue.a.run.app"))
        #expect(config.isAPIConfigured)
        #expect(config.apiBaseURL.host == "recanime-api-abcd-ue.a.run.app")
    }

    @Test("a string without a host is not configured")
    func hostlessURL() {
        let config = AppConfig.load(info: info(api: "not a url"))
        #expect(config.isAPIConfigured == false)
    }

    @Test("the override wins over the compiled value")
    func override() {
        let config = AppConfig.load(
            info: info(api: "https://recanime-api.example.run.app", env: "debug"),
            apiBaseURLOverride: "http://192.168.1.20:8080"
        )
        #expect(config.isAPIConfigured)
        #expect(config.apiBaseURL.host == "192.168.1.20")
    }

    @Test("a Release build pointed at plain http is not configured")
    func releaseRejectsHTTP() {
        let config = AppConfig.load(info: info(api: "http://192.168.1.20:8080"))
        #expect(config.environment == .release)
        #expect(config.isAPIConfigured == false)
    }

    @Test("a Debug build may point at plain http")
    func debugAllowsHTTP() {
        let config = AppConfig.load(info: info(api: "http://192.168.1.20:8080", env: "debug"))
        #expect(config.isAPIConfigured)
    }

    @Test("a Release build over https is configured")
    func releaseAllowsHTTPS() {
        let config = AppConfig.load(info: info(api: "https://recanime-api-abcd-ue.a.run.app"))
        #expect(config.environment == .release)
        #expect(config.isAPIConfigured)
    }

    @Test("a blank override leaves the compiled value in place")
    func blankOverride() {
        let config = AppConfig.load(info: info(api: "https://api.example.com"), apiBaseURLOverride: "  ")
        #expect(config.apiBaseURL.host == "api.example.com")
    }

    @Test("a Supabase URL without a host is dropped")
    func supabaseWithoutHost() {
        let config = AppConfig.load(info: info(supabase: "<project-ref>", key: "sb_publishable_x"))
        #expect(config.supabaseURL == nil)
        #expect(config.hasAuthConfiguration == false)
    }

    @Test("a complete Supabase configuration is reported as such")
    func supabaseConfigured() {
        let config = AppConfig.load(info: info(supabase: "https://abcd.supabase.co", key: "sb_publishable_x", env: "debug"))
        #expect(config.supabaseURL?.host == "abcd.supabase.co")
        #expect(config.hasAuthConfiguration)
        #expect(config.environment == .debug)
    }
}
