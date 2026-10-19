// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nerd",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Nerd",
            path: "Sources/Nerd",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ],
    swiftLanguageModes: [.v5]
)
