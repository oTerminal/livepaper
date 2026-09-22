/// The app's side of the render host and the sensors that feed it.
///
/// `ExtensionHostClient` is the one `RenderHost`: it writes `render-state.json`,
/// posts the Darwin notifications, reads the extension's heartbeat into a
/// status, and restarts WallpaperAgent when the host asks for it or goes quiet,
/// never more than once in ten minutes. The sensors (displays, power, lock,
/// sleep and wake, display sleep, covered displays) are `AsyncStream`s behind
/// small protocols; `ConditionsSensing` folds them into the `SensedConditions`
/// that the next render state carries. Nothing here needs a permission.
///
/// Global hotkeys, the login item and the rest of M7 land here later.
public enum LivepaperSystem {
    /// The unified log subsystem of the app's own lines: the app's bundle identifier.
    public static let logSubsystem = "app.livepaper.Livepaper"
}
