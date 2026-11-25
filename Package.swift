// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Compact",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CompactCore"),
        .executableTarget(
            name: "Compact",
            dependencies: ["CompactCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CompactCoreTests", dependencies: ["CompactCore"]),
    ]
)
