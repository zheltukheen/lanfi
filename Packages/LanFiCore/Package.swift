// swift-tools-version: 5.9
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
        .target(name: "LanFiCore"),
        .testTarget(name: "LanFiCoreTests", dependencies: ["LanFiCore"]),
    ]
)
