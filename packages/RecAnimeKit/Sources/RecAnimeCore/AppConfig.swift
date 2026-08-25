import Foundation

/// Build-time configuration injected through xcconfig → Info.plist (see apple/Configs).
public struct AppConfig: Sendable, Equatable {
    public enum Environment: String, Sendable {
        case debug
        case release
    }

    public var apiBaseURL: URL
    public var supabaseURL: URL?
    public var supabasePublishableKey: String
    public var environment: Environment

    public init(apiBaseURL: URL, supabaseURL: URL?, supabasePublishableKey: String, environment: Environment) {
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.environment = environment
    }

    /// Whether Supabase Auth is configured (Secrets.xcconfig present).
    public var hasAuthConfiguration: Bool {
        supabaseURL != nil && !supabasePublishableKey.isEmpty
    }

    /// Reads the configuration from the bundle's Info.plist. `apiBaseURLOverride` (set from the
    /// debug Settings screen) wins over the compiled value.
    public static func load(from bundle: Bundle = .main, apiBaseURLOverride: String? = nil) -> AppConfig {
        let info = bundle.infoDictionary ?? [:]
        func string(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let override = apiBaseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiString = override.isEmpty ? string("RAAPIBaseURL") : override
        let apiURL = URL(string: apiString) ?? URL(string: "http://localhost:8080")!
        let supabase = URL(string: string("RASupabaseURL")).flatMap { $0.host == nil ? nil : $0 }
        let env = Environment(rawValue: string("RAEnvironment")) ?? .release
        return AppConfig(apiBaseURL: apiURL, supabaseURL: supabase, supabasePublishableKey: string("RASupabasePublishableKey"), environment: env)
    }
}
