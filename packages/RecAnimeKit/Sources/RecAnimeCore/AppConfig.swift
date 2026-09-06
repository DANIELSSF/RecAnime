import Foundation

/// Build-time configuration injected through xcconfig → Info.plist (see apple/Configs).
public struct AppConfig: Sendable, Equatable {
    public enum Environment: String, Sendable {
        case debug
        case release
    }

    /// Host suffix of the placeholder URL shipped in the example xcconfig. A Release build that
    /// still points at it was never configured.
    private static let placeholderHostSuffix = ".example.run.app"

    public var apiBaseURL: URL
    public var supabaseURL: URL?
    public var supabasePublishableKey: String
    public var environment: Environment
    /// False when the build carries no usable API URL: empty, unparsable, hostless, or still the
    /// example placeholder. Release builds must say so instead of failing with "Sin conexión".
    public var isAPIConfigured: Bool

    public init(
        apiBaseURL: URL,
        supabaseURL: URL?,
        supabasePublishableKey: String,
        environment: Environment,
        isAPIConfigured: Bool = true
    ) {
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.environment = environment
        self.isAPIConfigured = isAPIConfigured
    }

    /// Whether Supabase Auth is configured (Secrets.xcconfig present).
    public var hasAuthConfiguration: Bool {
        supabaseURL != nil && !supabasePublishableKey.isEmpty
    }

    /// Reads the configuration from the bundle's Info.plist. `apiBaseURLOverride` (set from the
    /// debug Settings screen) wins over the compiled value.
    public static func load(from bundle: Bundle = .main, apiBaseURLOverride: String? = nil) -> AppConfig {
        load(info: bundle.infoDictionary ?? [:], apiBaseURLOverride: apiBaseURLOverride)
    }

    /// Info.plist dictionary variant, so the parsing rules can be unit-tested without a bundle.
    static func load(info: [String: Any], apiBaseURLOverride: String? = nil) -> AppConfig {
        func string(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let override = apiBaseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiString = override.isEmpty ? string("RAAPIBaseURL") : override
        let parsedAPI = apiString.isEmpty ? nil : URL(string: apiString)
        // A string without a host ("", "localhost:8080", garbage) still yields a relative URL.
        let apiHost = parsedAPI?.host?.lowercased()
        let configured = apiHost.map { !$0.hasSuffix(placeholderHostSuffix) } ?? false
        let apiURL = parsedAPI ?? URL(string: "http://localhost:8080")!
        let supabase = URL(string: string("RASupabaseURL")).flatMap { $0.host == nil ? nil : $0 }
        let env = Environment(rawValue: string("RAEnvironment")) ?? .release
        return AppConfig(
            apiBaseURL: apiURL,
            supabaseURL: supabase,
            supabasePublishableKey: string("RASupabasePublishableKey"),
            environment: env,
            isAPIConfigured: configured
        )
    }
}
