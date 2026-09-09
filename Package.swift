// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortKiller",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PortKiller",
            path: "Sources/PortKiller",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
