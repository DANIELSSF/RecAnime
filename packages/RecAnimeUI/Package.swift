// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RecAnimeUI",
    defaultLocalization: "es",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RecAnimeUI", targets: ["RecAnimeUI"]),
    ],
    targets: [
        .target(
            name: "RecAnimeUI",
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RecAnimeUITests",
            dependencies: ["RecAnimeUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
