import SwiftUI

/// Runs a change that came from a key press or a global hotkey. Such changes
/// never animate, including through a component's own `.animation(_:value:)`.
public func withoutAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    return try withTransaction(transaction, body)
}
