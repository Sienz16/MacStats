// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacStats",
            path: "Sources/MacStats"
        )
    ]
)
