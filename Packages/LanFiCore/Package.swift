// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LanFiCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LanFiCore", targets: ["LanFiCore"])
    ],
    targets: [
        .target(name: "LanFiCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "LanFiCoreTests",
            dependencies: ["LanFiCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
