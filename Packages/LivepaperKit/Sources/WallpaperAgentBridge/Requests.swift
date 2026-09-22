import Foundation
import LivepaperCore

/// Where the agent will show a surface, as far as its request says: each field
/// is `nil` when the request does not carry it.
public struct SurfaceDestination: Equatable, Sendable {
    /// The `CGDirectDisplayID` of the display. Key assignments by the display's
    /// UUID, which CoreGraphics gives for this ID; the ID itself is not kept.
    public var display: UInt32?
    /// In points.
    public var size: Size?
    /// Pixels per point.
    public var scale: Double?

    public init(display: UInt32?, size: Size?, scale: Double?) {
        self.display = display
        self.size = size
        self.scale = scale
    }
}

/// What a surface is showing for: WallpaperAgent's `WallpaperPresentationMode`.
/// The lock screen is the desktop's own surface in `.locked` (`Spikes/results/S3.md`).
public enum PresentationMode: Hashable, Sendable, CustomStringConvertible {
    /// The desktop, which the agent calls `default`.
    case desktop
    case locked
    /// The screen saver.
    case idle
    /// A mode this bridge has not seen, by the agent's name for it.
    case other(String)

    public init(agentName: String) {
        switch agentName {
        case "default": self = .desktop
        case "locked": self = .locked
        case "idle": self = .idle
        default: self = .other(agentName)
        }
    }

    /// The agent's name for the mode, which is what the log shows.
    public var description: String {
        switch self {
        case .desktop: "default"
        case .locked: "locked"
        case .idle: "idle"
        case let .other(name): name
        }
    }
}

/// WallpaperAgent's `WallpaperActivityState`.
public enum ActivityState: Hashable, Sendable, CustomStringConvertible {
    case active
    case suspended
    /// A state this bridge has not seen, by the agent's name for it.
    case other(String)

    public init(agentName: String) {
        switch agentName {
        case "active": self = .active
        case "suspended": self = .suspended
        default: self = .other(agentName)
        }
    }

    public var description: String {
        switch self {
        case .active: "active"
        case .suspended: "suspended"
        case let .other(name): name
        }
    }
}

/// The agent asks for a surface: a desktop, which the lock screen shares, or
/// the System Settings preview.
public struct AcquireRequest: Equatable, Sendable {
    /// The agent's identifier for the surface. A new one when the agent sent
    /// none the bridge could read, so that the surface still shows.
    public var surface: UUID
    public var destination: SurfaceDestination
    /// Whether this is the Settings preview. `false` when the request does not say.
    public var isPreview: Bool
    public var presentationMode: PresentationMode?
    public var activityState: ActivityState?

    public init(
        surface: UUID,
        destination: SurfaceDestination,
        isPreview: Bool,
        presentationMode: PresentationMode?,
        activityState: ActivityState?
    ) {
        self.surface = surface
        self.destination = destination
        self.isPreview = isPreview
        self.presentationMode = presentationMode
        self.activityState = activityState
    }
}

/// The agent tells a surface what it is showing for (locking, unlocking, the
/// screen saver) and where. Nothing needs to change in reply; the watchdog takes it
/// as a moment to check (docs/specs/M5-engine.md).
public struct UpdateRequest: Equatable, Sendable {
    /// `nil` when the agent sent no identifier the bridge could read: the
    /// update still says that something changed.
    public var surface: UUID?
    public var destination: SurfaceDestination
    public var presentationMode: PresentationMode?
    public var activityState: ActivityState?

    public init(surface: UUID?, destination: SurfaceDestination, presentationMode: PresentationMode?, activityState: ActivityState?) {
        self.surface = surface
        self.destination = destination
        self.presentationMode = presentationMode
        self.activityState = activityState
    }
}
