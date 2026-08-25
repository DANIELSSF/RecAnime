// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RecAnimeKit",
    defaultLocalization: "es",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        // Models, mappers, planners — no dependencies, shared with the widget extension.
        .library(name: "RecAnimeCore", targets: ["RecAnimeCore"]),
        // Networking, auth session and stores for the iPhone and Watch apps.
        .library(name: "RecAnimeKit", targets: ["RecAnimeKit"]),
        // Fixtures and mocks for previews and app tests.
        .library(name: "RecAnimeKitTesting", targets: ["RecAnimeKitTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.1"),
    ],
    targets: [
        .target(
            name: "RecAnimeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RecAnimeKit",
            dependencies: [
                "RecAnimeCore",
                .product(name: "Auth", package: "supabase-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RecAnimeKitTesting",
            dependencies: ["RecAnimeCore", "RecAnimeKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RecAnimeKitTests",
            dependencies: ["RecAnimeCore", "RecAnimeKit", "RecAnimeKitTesting"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
