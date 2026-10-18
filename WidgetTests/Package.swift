// swift-tools-version: 6.0
import PackageDescription

// Tests for the pure part of the widgets' shared code (WidgetShared/Core): the entries computed from LodestarKit and
// their words. The sources are the app's own files, reached through a symlink; they are compiled the way the Xcode
// targets compile them (Swift 5 mode with complete concurrency checking).
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
