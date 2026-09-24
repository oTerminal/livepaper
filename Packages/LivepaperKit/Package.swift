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
        .library(name: "LivepaperScene", targets: ["LivepaperScene"]),
        .library(name: "LivepaperTestSupport", targets: ["LivepaperTestSupport"]),
        .library(name: "LivepaperWorkshop", targets: ["LivepaperWorkshop"]),
        // Linked by the wallpaper extension and nothing else: all private API is here.
        .library(name: "WallpaperAgentBridge", targets: ["WallpaperAgentBridge"]),
    ],
    targets: [
        .target(name: "LivepaperCore", swiftSettings: approachableConcurrency),
        // Wallpaper Engine scenes (record 0007): their files, and the seam a scene is drawn through.
        .target(name: "LivepaperScene", dependencies: ["LivepaperCore"], swiftSettings: approachableConcurrency),
        .target(name: "LivepaperImport", dependencies: ["LivepaperCore", "LivepaperScene"], swiftSettings: approachableConcurrency),
        .target(name: "LivepaperPlayback", dependencies: ["LivepaperCore", "LivepaperScene"], swiftSettings: approachableConcurrency),
        .target(name: "LivepaperSystem", dependencies: ["LivepaperCore"], swiftSettings: mainActorByDefault),
        // The Objective-C declarations of the private wallpaper-extension API, since a package has no bridging header.
        .target(name: "WallpaperAgentBridgeObjC"),
        .target(
            name: "WallpaperAgentBridge",
            dependencies: ["WallpaperAgentBridgeObjC", "LivepaperCore"],
            swiftSettings: approachableConcurrency
        ),
        // Fakes and deterministic inputs, for this package's tests and for screens built on fakes (M6).
        .target(
            name: "LivepaperTestSupport",
            dependencies: ["LivepaperCore", "LivepaperImport", "LivepaperSystem"],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "LivepaperCoreTests",
            dependencies: ["LivepaperCore", "LivepaperTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "LivepaperSceneTests",
            dependencies: ["LivepaperScene", "LivepaperCore", "LivepaperTestSupport"],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "LivepaperImportTests",
            dependencies: ["LivepaperImport", "LivepaperScene", "LivepaperCore", "LivepaperTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "LivepaperPlaybackTests",
            dependencies: ["LivepaperPlayback", "LivepaperScene", "LivepaperCore", "LivepaperTestSupport"],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "LivepaperSystemTests",
            dependencies: ["LivepaperSystem", "LivepaperCore", "LivepaperTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "WallpaperAgentBridgeTests",
            dependencies: ["WallpaperAgentBridge", "LivepaperCore"],
            swiftSettings: approachableConcurrency
        ),
        // Wallpaper Engine Workshop items, downloaded with the user's own Steam login through Valve's steamcmd (record 0009).
        .target(name: "LivepaperWorkshop", dependencies: ["LivepaperImport"], swiftSettings: approachableConcurrency),
        .testTarget(
            name: "LivepaperWorkshopTests",
            dependencies: ["LivepaperWorkshop", "LivepaperImport"],
            resources: [.copy("Fixtures")],
            swiftSettings: approachableConcurrency
        ),
    ]
)
