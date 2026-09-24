/// Core's form of the design system's `StatusLineStatus`, which Core cannot
/// import: the app maps one to the other, case for case.
public enum StatusLineContent: Equatable, Sendable {
    case idle(String)
    case working(String)
    /// The wallpaper service has stopped answering, and Restart is offered.
    case serviceNotResponding
}

/// The status line's words.
///
/// A service that is not responding comes first, because only the user can
/// act on it; then an import, which takes the line while it runs; then the
/// render host's own work; then what it is showing. `showing` is how many
/// displays the render state shows, and `importing` the running import's place
/// in the list and the list's length.
public func statusLine(
    host: RenderHostStatus, showing: Int, isPausedAll: Bool, importing: (position: Int, count: Int)?
) -> StatusLineContent {
    if host == .recovering(.restartAgent) { return .serviceNotResponding }
    if let importing {
        return .working(importing.count > 1 ? "Importing \(importing.position) of \(importing.count)" : "Importing")
    }
    switch host {
    case .connecting: return .working("Connecting to the wallpaper service")
    case .recovering: return .working("Recovering the wallpaper")
    case .notSelected: return .idle("Livepaper is not your wallpaper")
    case .unavailable: return .idle("Not available on this version of macOS")
    case .stopped: return .idle(isPausedAll ? "Paused" : "Stopped")
    case .live: return .idle(isPausedAll ? "Paused" : liveWords(showing: showing))
    }
}

private func liveWords(showing: Int) -> String {
    switch showing {
    case 0: "No wallpaper set"
    case 1: "Live on 1 display"
    default: "Live on \(showing) displays"
    }
}
