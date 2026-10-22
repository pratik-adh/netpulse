// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Netpulse",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Netpulse",
            path: "Sources/Netpulse"
        )
    ],
    // Pinned so a newer toolchain defaulting to Swift 6 strict concurrency
    // doesn't turn AppKit's main-actor warnings into build errors.
    swiftLanguageVersions: [.v5]
)
