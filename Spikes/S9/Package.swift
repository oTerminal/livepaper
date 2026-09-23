// swift-tools-version: 6.0
// S9: read Wallpaper Engine scene items and draw them with Metal. Spike code, shaped as the starting point
// for the product: the format reader, the shader translation, the import step and the renderer are separate
// targets. Results in ../results/S9.md.
import PackageDescription

let package = Package(
    name: "S9",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SceneItemFormat", targets: ["SceneItemFormat"]),
        .library(name: "SceneShaderTranslation", targets: ["SceneShaderTranslation"]),
        .library(name: "SceneImport", targets: ["SceneImport"]),
        .library(name: "SceneItemRenderer", targets: ["SceneItemRenderer"]),
    ],
    targets: [
        // .pkg, .tex, .mdl and the scene / model / material / effect / particle JSON. No Metal.
        .target(name: "SceneItemFormat"),
        // Workshop GLSL → MSL (glslang, SPIRV-Cross), with our replacements for Wallpaper Engine's headers.
        .target(name: "SceneShaderTranslation", resources: [.copy("Resources/include")]),
        // Import time: every program a scene draws with, translated, in a manifest. Our base materials.
        .target(name: "SceneImport", dependencies: ["SceneItemFormat", "SceneShaderTranslation"],
                resources: [.copy("Resources/materials")]),
        // Load and draw with Metal. Never runs the translator.
        .target(name: "SceneItemRenderer", dependencies: ["SceneItemFormat", "SceneShaderTranslation", "SceneImport"]),
        // The spike's command line: inventory, translation table, import, offscreen renders.
        .executableTarget(name: "s9", dependencies: ["SceneItemFormat", "SceneShaderTranslation", "SceneImport",
                                                     "SceneItemRenderer"]),
    ],
    swiftLanguageModes: [.v6]
)
