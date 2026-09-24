/// One card of first-run onboarding (M7).
public enum OnboardingStep: Hashable, Sendable, CaseIterable {
    /// A file dropped on the card or chosen, or a sample, imported and set on
    /// every display. The card's title says "Add a wallpaper", as the spec names it.
    case importWallpaper
    /// "Open at login": the login item, registered and shown as macOS has it.
    case openAtLogin
    /// "Make Livepaper your wallpaper": Livepaper selected as the system wallpaper.
    case selectLivepaper
}

/// What earlier launches left in the preferences about onboarding.
public struct OnboardingRecord: Hashable, Sendable {
    /// The version of Livepaper that ran onboarding; nil before any has.
    public var onboardedVersion: String?
    /// The user left Livepaper as their wallpaper, from Settings: the next
    /// launch offers to make it the wallpaper again, and nothing else.
    public var hasLeft: Bool

    public init(onboardedVersion: String? = nil, hasLeft: Bool = false) {
        self.onboardedVersion = onboardedVersion
        self.hasLeft = hasLeft
    }

    /// Leaving Livepaper, recorded before the app quits.
    public func leaving() -> OnboardingRecord {
        var record = self
        record.hasLeft = true
        return record
    }
}

/// What a launch shows before anything else.
public enum OnboardingPlan: Hashable, Sendable {
    /// Nothing: onboarding ran before, under this version or an earlier one.
    case nothing
    /// These cards, in this order.
    case steps([OnboardingStep])
    /// Run from the folder Gatekeeper copies a downloaded app to: one card asks
    /// for Livepaper to be moved to Applications, and nothing is registered or
    /// written, since the next launch would be from another path.
    case moveToApplications

    /// Whether this launch starts Livepaper: reads the library, activates the
    /// render host, opens the command socket and starts the sensors. A
    /// translocated launch shows the move card and nothing else, and writes
    /// nothing, at quit included.
    public var startsLivepaper: Bool { self != .moveToApplications }

    /// What to keep once this plan's cards end, by their last button or their
    /// window closed: the version that ran onboarding, the first one to run it
    /// staying, and leaving forgotten. Nil when nothing is written: nothing was
    /// shown, or this copy is translocated.
    public func record(afterEnding record: OnboardingRecord, version: String) -> OnboardingRecord? {
        guard case .steps = self else { return nil }
        return OnboardingRecord(onboardedVersion: record.onboardedVersion ?? version, hasLeft: false)
    }
}

/// Which cards a launch shows (M7's first-launch table).
///
/// - Translocated: the move card alone, whatever was recorded.
/// - After leaving: making Livepaper the wallpaper again, alone.
/// - Onboarded before, by this version or an earlier one (an update): nothing;
///   the login item is squared with its intent as at every launch.
/// - Nothing recorded, but a library or an app state on disk (`ranBefore`): a
///   Livepaper from before onboarding ran here, which is an update too.
/// - Otherwise, a fresh install: the three steps. Selecting writes nothing when
///   the store names Livepaper already, and completes on the heartbeat's flag.
public func onboardingPlan(record: OnboardingRecord, ranBefore: Bool, isTranslocated: Bool) -> OnboardingPlan {
    if isTranslocated { return .moveToApplications }
    if record.hasLeft { return .steps([.selectLivepaper]) }
    if record.onboardedVersion != nil || ranBefore { return .nothing }
    return .steps(OnboardingStep.allCases)
}

/// What the "Open at login" card says: macOS's status, and whether the card
/// asked for the login item. It never claims what macOS does not report.
public enum OnboardingLoginPhase: Hashable, Sendable {
    /// Not asked yet: Open at Login, or Not Now.
    case asking
    /// macOS had it on before the card asked.
    case alreadyOn
    /// Asked, and macOS has it on: the card moves on by itself.
    case turnedOn
    /// Registered, and waiting for the user to allow it in Login Items.
    case needsApproval
    /// macOS cannot find the app to register, usually because it is not in Applications.
    case notFound
    /// Asked, and macOS still has it off: registering failed.
    case notRegistered

    /// Whether the card goes on to the next one by itself.
    public var movesOn: Bool { self == .turnedOn }
}

public func onboardingLoginPhase(asked: Bool, status: LoginItemStatus) -> OnboardingLoginPhase {
    switch status {
    case .on: asked ? .turnedOn : .alreadyOn
    case .needsApproval: .needsApproval
    case .notFound: .notFound
    case .off: asked ? .notRegistered : .asking
    }
}
