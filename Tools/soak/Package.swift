// swift-tools-version: 6.2
import PackageDescription

// The soak's report tool. Its logic is `LivepaperSoak`, in LivepaperKit; this is
// only the command that reads the files and prints the Markdown. Shipped with nothing.
let package = Package(
    name: "SoakTools",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../Packages/LivepaperKit")],
    targets: [
        .executableTarget(
            name: "soak-report",
            dependencies: [.product(name: "LivepaperSoak", package: "LivepaperKit")],
            path: "Sources/soak-report",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
