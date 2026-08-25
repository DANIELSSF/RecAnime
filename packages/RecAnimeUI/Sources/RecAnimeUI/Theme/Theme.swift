import SwiftUI

/// RecAnime design tokens. Every color in the apps comes from here (the token lint script
/// in apple/scripts fails on hard-coded colors anywhere else). One accent hue family only.
public enum Theme {
    // MARK: Accent family (violet / indigo)

    /// Primary accent: tint, selected chips, progress, "Viendo".
    public static let accent = adaptive(light: 0x6E5BFF, dark: 0x8577FF)
    /// Deep accent for gradient ends and pressed states.
    public static let accentDeep = adaptive(light: 0x4A3BD9, dark: 0x5A4BEA)
    /// Soft accent fill for selected rows and badges.
    public static var accentSoft: Color {
        accent.opacity(0.14)
    }

    // MARK: Status colors (same hue family, shifted)

    public static let statusPending = adaptive(light: 0x8E8AB5, dark: 0x9A96C4)
    public static var statusWatching: Color {
        accent
    }

    public static let statusWatched = adaptive(light: 0x4F6BFF, dark: 0x6C84FF)
    public static let favorite = adaptive(light: 0xC05BFF, dark: 0xCE7BFF)

    /// Color for a library status (`pending` / `watching` / `watched`).
    public static func status(_ status: String) -> Color {
        switch status {
        case "watching": statusWatching
        case "watched": statusWatched
        default: statusPending
        }
    }

    // MARK: Gradients

    public static var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var progressGradient: LinearGradient {
        LinearGradient(colors: [accent, statusWatched], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Radii and spacing

    public enum Radius {
        public static let thumb: CGFloat = 8
        public static let poster: CGFloat = 12
        public static let card: CGFloat = 16
        public static let sheet: CGFloat = 24
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: Helpers

    /// Builds a color that adapts to light/dark on iOS and macOS; watchOS is always dark.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(watchOS)
            return Color(hex: dark)
        #elseif canImport(UIKit)
            return Color(UIColor { traits in
                UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
            })
        #elseif canImport(AppKit)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(Color(hex: isDark ? dark : light))
            })
        #else
            return Color(hex: light)
        #endif
    }
}

extension Color {
    /// Token-only hex initializer (allowed here; everywhere else use Theme).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
