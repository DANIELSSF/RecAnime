import Foundation

/// Single source of truth for bundle-level identifiers shared by the iPhone app, the Watch app
/// and the widget extension. Keep in sync with apple/project.yml.
public enum Identifiers {
    public static let bundleID = "com.danielsantiago.recanime"
    public static let watchBundleID = "com.danielsantiago.recanime.watchkitapp"
    public static let widgetsBundleID = "com.danielsantiago.recanime.watchkitapp.widgets"
    public static let appGroup = "group.com.danielsantiago.recanime"
    public static let urlScheme = "recanime"
    public static let backgroundRefreshTask = "com.danielsantiago.recanime.refresh"
    public static let nextEpisodeWidgetKind = "com.danielsantiago.recanime.nextEpisode"
    public static let episodeAiredCategory = "EPISODE_AIRED"
    public static let keychainService = "com.danielsantiago.recanime.auth"

    /// Deep link to an anime page: `recanime://anime/<malId>`.
    public static func animeURL(malID: Int) -> URL {
        URL(string: "\(urlScheme)://anime/\(malID)")!
    }
}
