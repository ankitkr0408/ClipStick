// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipCoard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipCoard",
            path: "Sources/ClipCoard",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
