// swift-tools-version: 6.0
import PackageDescription

// Tests for the pure part of the widgets' shared code (WidgetShared/Core): the entries computed from LodestarKit and
// their words. The sources are the app's own files, reached through a symlink; they are compiled the way the Xcode
// targets compile them (Swift 5 mode with complete concurrency checking).
//
// ForecastCore does the same for the cloud forecast's services (Lodestar/Services/Forecast*.swift and OnlineFeed.swift):
// the reading of MET Norway's answer, the night's dew, wind, fog and temperature, and their words.
let package = Package(
    name: "WidgetTests",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    dependencies: [
        .package(path: "../LodestarKit"),
    ],
    targets: [
        .target(
            name: "TonightCore",
            dependencies: [.product(name: "LodestarKit", package: "LodestarKit")],
            path: "Sources/TonightCore",
            swiftSettings: [.swiftLanguageMode(.v5), .enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "ForecastCore",
            dependencies: [.product(name: "LodestarKit", package: "LodestarKit")],
            path: "Sources/ForecastCore",
            swiftSettings: [.swiftLanguageMode(.v5), .enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ForecastCoreTests",
            dependencies: [
                "ForecastCore",
                .product(name: "LodestarKit", package: "LodestarKit"),
            ],
            path: "Tests/ForecastCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TonightCoreTests",
            dependencies: [
                "TonightCore",
                .product(name: "LodestarKit", package: "LodestarKit"),
            ],
            path: "Tests/TonightCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
