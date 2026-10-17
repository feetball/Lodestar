// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LodestarKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LodestarKit", targets: ["LodestarKit"]),
    ],
    targets: [
        .target(
            name: "LodestarKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LodestarKitTests",
            dependencies: ["LodestarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
