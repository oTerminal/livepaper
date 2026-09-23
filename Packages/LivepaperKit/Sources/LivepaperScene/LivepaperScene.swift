/// Wallpaper Engine scenes (record 0007, docs/specs/M11-wallpaper-engine-scenes.md).
///
/// What the product knows of a scene's files: `ScenePackage` reads a `.pkg`,
/// `SpriteSheet` a `.tex` whose pictures are a sprite sheet, and
/// `readSceneOutline` what an import needs from the scene's JSON, the GIF-scene
/// rule among it. The rest is the seam a scene is drawn through: `SceneDrawing`,
/// the stand-in that draws its poster (`PosterScene`), and the import-time hook
/// (`ScenePreparation`). Spike S9's renderer is ported in behind the seam.
public enum LivepaperScene {
    /// The rate a scene is drawn at. Heavy scenes could not hold 60 on the
    /// spike's Mac while light ones held either (`Spikes/results/S10.md`).
    public static let framesPerSecond = 30.0
}
