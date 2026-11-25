// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Compact",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "CompactCore"),
        .executableTarget(
            name: "Compact",
            dependencies: [
                "CompactCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CompactCoreTests", dependencies: ["CompactCore"]),
    ]
)
