// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MacStats",
            path: "Sources/MacStats"
        )
    ]
)
