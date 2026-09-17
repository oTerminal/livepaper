import Foundation

/// A physical display, identified by the UUID macOS assigns to it.
///
/// The UUID survives unplugging, replugging and reordering, unlike a screen's
/// index or its `CGDirectDisplayID`, so assignments keyed by it are remembered
/// while a display is disconnected.
public struct DisplayIdentity: Hashable, Codable, Sendable {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }
}
