// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aether",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aether", targets: ["AetherApp"]),
        .executable(name: "AetherBridge", targets: ["AetherBridge"]),
        .executable(name: "AetherService", targets: ["AetherService"])
    ],
    targets: [
        .target(name: "AetherCore"),
        .executableTarget(name: "AetherApp", dependencies: ["AetherCore"]),
        .executableTarget(name: "AetherBridge", dependencies: ["AetherCore"]),
        .executableTarget(name: "AetherService", dependencies: ["AetherCore"]),
        .testTarget(name: "AetherCoreTests", dependencies: ["AetherCore"])
    ],
    swiftLanguageModes: [.v5]
)
