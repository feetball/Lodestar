// swift-tools-version: 6.0
import PackageDescription

// Unit tests for the app's own logic: the services, models and formatters of Lodestar/ that need nothing but Foundation,
// Observation, CoreLocation, Network and LodestarKit. The sources are the app's own files, reached through one symlink per file
// (AppTests/sync-links.sh builds them from appcore-files.txt) and compiled the way the Xcode target compiles them (Swift 5 mode
// with complete concurrency checking). Views, the camera, the motion sensors and the Watch link are not in it: they need UIKit,
// SwiftUI, AVFoundation or CoreMotion. `swift test` runs on the Mac, without a simulator.
let package = Package(
    name: "AppTests",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../LodestarKit"),
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: [.product(name: "LodestarKit", package: "LodestarKit")],
            path: "Sources/AppCore",
            swiftSettings: [.swiftLanguageMode(.v5), .enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: [
                "AppCore",
                .product(name: "LodestarKit", package: "LodestarKit"),
            ],
            path: "Tests/AppCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
