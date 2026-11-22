// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipStick",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipStick",
            path: "Sources/ClipStick",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
