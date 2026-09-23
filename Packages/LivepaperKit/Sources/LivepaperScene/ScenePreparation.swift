import Foundation

/// The work a scene needs at import, before it is committed to the library.
public enum ScenePreparation {
    /// Runs on the scene's folder in `.staging/`, with the item's files
    /// already copied in (`SceneFolder`). Whatever it writes there is committed
    /// with them; if it throws, the import fails and leaves nothing behind.
    ///
    /// Nothing to do yet. This is where spike S9's import-time work plugs in:
    /// translating the scene's shaders to Metal once, rather than at every
    /// launch of the extension.
    public static func prepare(_ folder: URL) async throws {}
}
