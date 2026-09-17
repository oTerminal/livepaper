// swift-tools-version: 6.2
import PackageDescription

// Approachable Concurrency, spelled out for SwiftPM. The remaining features in
// that Xcode setting are already part of the Swift 6 language mode.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

// Libraries ship nonisolated APIs; only the system-facing module defaults to the main actor.
let mainActorByDefault: [SwiftSetting] = approachableConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "LivepaperKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LivepaperCore", targets: ["LivepaperCore"]),
        .library(name: "LivepaperImport", targets: ["LivepaperImport"]),
        .library(name: "LivepaperPlayback", targets: ["LivepaperPlayback"]),
        .library(name: "LivepaperSystem", targets: ["LivepaperSystem"]),
    ],
    targets: [
        .target(name: "LivepaperCore", swiftSettings: approachableConcurrency),
        .target(name: "LivepaperImport", dependencies: ["LivepaperCore"], swiftSettings: approachableConcurrency),
        .target(name: "LivepaperPlayback", dependencies: ["LivepaperCore"], swiftSettings: approachableConcurrency),
        .target(name: "LivepaperSystem", dependencies: ["LivepaperCore"], swiftSettings: mainActorByDefault),
        .testTarget(name: "LivepaperCoreTests", dependencies: ["LivepaperCore"], swiftSettings: approachableConcurrency),
    ]
)
