// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyPace",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "KeyPace",
            path: "Sources/KeyPace",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "KeyPaceTests",
            dependencies: ["KeyPace"],
            path: "Tests/KeyPaceTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
