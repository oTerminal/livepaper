import Foundation
import Testing
import LivepaperWorkshop

/// What Livepaper types into steamcmd's console, and when, for each job.
struct SteamConversationTests {
    typealias Effect = SteamConversation.Effect

    static let lonelyCat = WorkshopItemID(3_289_988_463)!
    static let folder = "/Users/someone/Library/Application Support/Steam/steamapps/workshop/content/431960/3289988463"

    /// Feeds the lines in order and gathers every effect.
    static func talk(_ job: SteamJob, _ lines: [SteamLine]) -> [Effect] {
        talk(job, runs: [lines])
    }

    /// Feeds each run of steamcmd's lines in order, steamcmd going by itself between runs, and gathers every effect.
    static func talk(_ job: SteamJob, runs: [[SteamLine]]) -> [Effect] {
        var conversation = SteamConversation(job: job)
        var effects: [Effect] = []
        for (index, lines) in runs.enumerated() {
            if index > 0 { effects += conversation.exited(status: 0) }
            effects += lines.flatMap { conversation.read($0) }
        }
        return effects
    }

    // MARK: Downloading

    @Test func `a download with the saved login signs in, downloads, then quits`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .updating(percent: 0), .updating(percent: nil), .console,
            .savedLogin, .other, .other, .signedIn, .console,
            .downloading(Self.lonelyCat), .downloaded(Self.lonelyCat, folder: Self.folder, bytes: 4_404_844), .console,
            .other,
        ])
        #expect(effects == [
            .report(.updating(percent: 0)), .report(.updating(percent: nil)),
            .type("login someone"), .report(.signingIn),
            .type("workshop_download_item 431960 3289988463"), .report(.downloading),
            .finish(.success(.downloaded(folder: Self.folder, bytes: 4_404_844))),
            .type("quit"),
        ])
    }

    @Test func `a download never answers a password prompt: the saved login has gone`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [.console, .noSavedLogin, .other, .passwordPrompt])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.failure(.signInNeeded)), .stop])
    }

    @Test func `a download never answers a Steam Guard prompt either`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [.console, .codePrompt(.email)])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.failure(.signInNeeded)), .stop])
    }

    static let downloadRefusals: [Row<SteamLine, WorkshopError>] = [
        Row("seen: an item Steam does not have", .downloadFailed(lonelyCat, "File Not Found"), .itemNotFound),
        Row("seen: what an account without Wallpaper Engine is told", .downloadFailed(lonelyCat, "Failure"), .notOwned),
        Row("denied outright", .downloadFailed(lonelyCat, "Access Denied"), .notOwned),
        Row("out of time", .downloadFailed(lonelyCat, "Timeout"), .timedOut),
        Row("anything else, in Steam's words", .downloadFailed(lonelyCat, "Disk Write Failure"), .steamSaid("Disk Write Failure")),
    ]

    @Test(arguments: downloadRefusals)
    func `a download Steam refuses says why`(row: Row<SteamLine, WorkshopError>) {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .console, .savedLogin, .signedIn, .console, .downloading(Self.lonelyCat), row.input, .console,
        ])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(row.expected)), .type("quit")])
    }

    @Test func `another item's result is not this one's`() {
        let other = WorkshopItemID(1)!
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .console, .signedIn, .console, .downloaded(other, folder: "/elsewhere", bytes: 1), .console,
        ])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.noAnswer)), .type("quit")])
    }

    @Test func `a download whose sign-in fails does not download`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .console, .savedLogin, .signInFailed("No Connection"), .console,
        ])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.failure(.noConnection)), .type("quit")])
    }

    @Test func `the console back without a sign-in is no sign-in`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [.console, .other, .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.noAnswer)), .type("quit")])
    }

    // MARK: Signing in

    @Test func `a sign-in types the password once, at its prompt`() {
        let effects = Self.talk(.signIn(account: "someone"), [
            .console, .noSavedLogin, .other, .passwordPrompt, .other, .other, .signedIn, .console,
        ])
        #expect(effects == [
            .type("login someone"), .report(.signingIn), .typePassword,
            .finish(.success(.signedIn)), .type("quit"),
        ])
    }

    @Test func `a sign-in asks for the code Steam Guard wants`() {
        let effects = Self.talk(.signIn(account: "someone"), [
            .console, .passwordPrompt, .other, .other, .codePrompt(.email),
        ])
        #expect(Array(effects.suffix(1)) == [.askForCode(.email, again: false)])
    }

    @Test func `a code asked for a second time says the first was wrong`() {
        let effects = Self.talk(.signIn(account: "someone"), [
            .console, .passwordPrompt, .codePrompt(.authenticator), .codePrompt(.authenticator),
        ])
        #expect(Array(effects.suffix(2)) == [.askForCode(.authenticator, again: false), .askForCode(.authenticator, again: true)])
    }

    @Test func `a sign-in waiting for the Steam Mobile app says so once`() {
        let effects = Self.talk(.signIn(account: "someone"), [
            .console, .passwordPrompt, .other, .awaitingApproval, .awaitingApproval, .awaitingApproval, .other, .signedIn, .console,
        ])
        #expect(effects == [
            .type("login someone"), .report(.signingIn), .typePassword, .report(.waitingForApproval),
            .finish(.success(.signedIn)), .type("quit"),
        ])
    }

    @Test func `a second password prompt is a password Steam refused`() {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .passwordPrompt, .passwordPrompt])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.wrongPassword)), .stop])
    }

    @Test func `a sign-in with the saved login still in place needs no password`() {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .savedLogin, .signedIn, .console])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.success(.signedIn)), .type("quit")])
    }

    static let signInRefusals: [Row<String, WorkshopError>] = [
        Row("log: a wrong account name or password", "Invalid Password", .wrongPassword),
        Row("a wrong code from the app", "Two-factor code mismatch", .wrongCode),
        Row("a wrong code from the email", "Invalid Login Auth Code", .wrongCode),
        Row("a code that has expired", "Expired Login Auth Code", .wrongCode),
        Row("too many tries", "Rate Limit Exceeded", .rateLimited),
        Row("too many tries, said another way", "Account Login Denied Throttle", .rateLimited),
        Row("log: Steam not answering", "Timeout", .timedOut),
        Row("no network", "No Connection", .noConnection),
        Row("Steam down", "Service Unavailable", .noConnection),
        Row("anything else, in Steam's words", "Account Disabled", .steamSaid("Account Disabled")),
    ]

    @Test(arguments: signInRefusals)
    func `a sign-in Steam refuses says why`(row: Row<String, WorkshopError>) {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .passwordPrompt, .signInFailed(row.input), .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(row.expected)), .type("quit")])
    }

    // MARK: A saved login Steam refuses

    /// A saved login steamcmd tried and Steam refused, then back at the console: whether it is logged out of.
    static let savedLoginRefusals: [Row<String, [Effect]>] = [
        Row("seen after a sign-out stopped at a prompt: the revoked login", "Access Denied", [.type("logout")]),
        Row("a login Steam no longer takes", "Invalid Password", [.type("logout")]),
        Row("anything else Steam says of the login", "Expired Login Auth Code", [.type("logout")]),
        Row("no network: the login may be fine", "No Connection", [.finish(.failure(.noConnection)), .type("quit")]),
        Row("Steam not answering", "Timeout", [.finish(.failure(.timedOut)), .type("quit")]),
        Row("too many tries", "Rate Limit Exceeded", [.finish(.failure(.rateLimited)), .type("quit")]),
    ]

    @Test(arguments: savedLoginRefusals)
    func `a sign-in logs out of a saved login Steam refuses, but not of one it could not ask about`(row: Row<String, [Effect]>) {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .savedLogin, .signInFailed(row.input), .console])
        #expect(effects == [.type("login someone"), .report(.signingIn)] + row.expected)
    }

    @Test func `a refused saved login is logged out of, written down by quitting, and the password asked for`() {
        let effects = Self.talk(.signIn(account: "someone"), runs: [
            [.console, .savedLogin, .signInFailed("Access Denied"), .console, .other, .console, .other],
            [.console, .noSavedLogin, .passwordPrompt, .signedIn, .console],
        ])
        #expect(effects == [
            .type("login someone"), .report(.signingIn), .type("logout"), .type("quit"), .restart,
            .type("login someone"), .report(.signingIn), .typePassword,
            .finish(.success(.signedIn)), .type("quit"),
        ])
    }

    @Test func `a saved login refused again after logging out of it ends the sign-in`() {
        let refused: [SteamLine] = [.console, .savedLogin, .signInFailed("Access Denied"), .console]
        let effects = Self.talk(.signIn(account: "someone"), runs: [refused + [.console], refused])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.steamSaid("Access Denied"))), .type("quit")])
    }

    @Test func `a download whose saved login Steam refuses asks to sign in`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .console, .savedLogin, .signInFailed("Access Denied"), .console,
        ])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.failure(.signInNeeded)), .type("quit")])
    }

    @Test func `a password Steam denies is not a saved login to log out of`() {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .passwordPrompt, .signInFailed("Access Denied"), .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.steamSaid("Access Denied"))), .type("quit")])
    }

    // MARK: Signing out

    /// steamcmd forgets a login at `logout` but writes that down only when it quits (seen on
    /// 2026-09-24: stopped at the password prompt after `logout`, it kept the revoked login, and
    /// the next sign-in was refused with it). So it quits, and a second run proves the login gone.
    @Test func `signing out logs out, quits so that steamcmd writes it down, then proves the login gone`() {
        let effects = Self.talk(.signOut(account: "someone"), runs: [
            [.console, .savedLogin, .signedIn, .console, .other, .console, .other],
            [.console, .noSavedLogin, .passwordPrompt],
        ])
        #expect(effects == [
            .type("login someone"), .report(.signingOut),
            .type("logout"), .type("quit"), .restart,
            .type("login someone"),
            .finish(.success(.signedOut)), .stop,
        ])
    }

    /// Signed in with the saved login, logged out and quit: what the next run says, and how the sign-out ends.
    static let afterLogout: [Row<[SteamLine], [Effect]>] = [
        Row("the saved login gone: signed out", [.console, .noSavedLogin], [.finish(.success(.signedOut)), .stop]),
        Row("asked for the password: signed out", [.console, .passwordPrompt], [.finish(.success(.signedOut)), .stop]),
        Row(
            "the saved login still there: not signed out",
            [.console, .savedLogin, .signedIn, .console],
            [.finish(.failure(.stillSignedIn)), .type("quit")]
        ),
        Row(
            "Steam cannot be reached to try: not known to be signed out",
            [.console, .signInFailed("No Connection"), .console],
            [.finish(.failure(.noConnection)), .type("quit")]
        ),
        Row("back at the console with neither", [.console, .other, .console], [.finish(.failure(.noAnswer)), .type("quit")]),
    ]

    @Test(arguments: afterLogout)
    func `a sign-out succeeds only when the saved login is seen to be gone`(row: Row<[SteamLine], [Effect]>) {
        let signedIn: [SteamLine] = [.console, .savedLogin, .signedIn, .console, .console]
        let effects = Self.talk(.signOut(account: "someone"), runs: [signedIn, row.input])
        let loggedOut: [Effect] = [.type("login someone"), .report(.signingOut), .type("logout"), .type("quit"), .restart]
        #expect(effects == loggedOut + [.type("login someone")] + row.expected)
    }

    @Test func `steamcmd failing to go after logout is a failure`() {
        var conversation = SteamConversation(job: .signOut(account: "someone"))
        for line: SteamLine in [.console, .savedLogin, .signedIn, .console, .console] {
            _ = conversation.read(line)
        }
        #expect(conversation.exited(status: 6) == [.finish(.failure(.toolStopped(status: 6)))])
    }

    @Test func `signing out with a saved login Steam refuses logs out of it too`() {
        let effects = Self.talk(.signOut(account: "someone"), runs: [
            [.console, .savedLogin, .signInFailed("Access Denied"), .console, .console],
            [.console, .noSavedLogin],
        ])
        #expect(effects == [
            .type("login someone"), .report(.signingOut), .type("logout"), .type("quit"), .restart,
            .type("login someone"), .finish(.success(.signedOut)), .stop,
        ])
    }

    @Test func `signing out with no saved login has nothing to take back`() {
        let effects = Self.talk(.signOut(account: "someone"), [.console, .noSavedLogin, .passwordPrompt])
        #expect(effects == [.type("login someone"), .report(.signingOut), .finish(.success(.signedOut)), .stop])
    }

    @Test func `signing out when Steam cannot be reached says so`() {
        let effects = Self.talk(.signOut(account: "someone"), [.console, .savedLogin, .signInFailed("No Connection"), .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.noConnection)), .type("quit")])
    }

    // MARK: Setting up, and ending

    @Test func `setting up lets steamcmd update itself, then quits`() {
        let effects = Self.talk(.update, [.updating(percent: 0), .updating(percent: 45), .updating(percent: 100), .console])
        #expect(effects == [
            .report(.updating(percent: 0)), .report(.updating(percent: 45)), .report(.updating(percent: 100)),
            .finish(.success(.updated)), .type("quit"),
        ])
    }

    @Test func `steamcmd restarting itself after an update starts the job again`() {
        var conversation = SteamConversation(job: .signIn(account: "someone"))
        _ = conversation.read(.updating(percent: 100))
        #expect(conversation.exited(status: 42) == [.restart])
        #expect(conversation.read(.console) == [.type("login someone"), .report(.signingIn)])
        #expect(conversation.read(.passwordPrompt) == [.typePassword])
    }

    @Test func `steamcmd ending before the job is done is a failure`() {
        var conversation = SteamConversation(job: .download(Self.lonelyCat, account: "someone"))
        _ = conversation.read(.console)
        #expect(conversation.exited(status: 1) == [.finish(.failure(.toolStopped(status: 1)))])
    }

    @Test func `steamcmd ending after the job is done is how it should end`() {
        var conversation = SteamConversation(job: .signIn(account: "someone"))
        for line: SteamLine in [.console, .savedLogin, .signedIn, .console] {
            _ = conversation.read(line)
        }
        #expect(conversation.exited(status: 0) == [])
        #expect(conversation.isFinished)
    }

    @Test func `nothing is typed after the job is done but quit`() {
        let effects = Self.talk(.signIn(account: "someone"), [
            .console, .savedLogin, .signedIn, .console, .console, .passwordPrompt, .codePrompt(.email),
        ])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.success(.signedIn)), .type("quit")])
    }

    static let accountNames: [Row<String, Bool>] = [
        Row("letters, digits and underscores", "some_one2007", true),
        Row("a name that would be two commands", "someone\nlogout", false),
        Row("a name with a space, which would pass steamcmd a password", "someone hunter2", false),
        Row("a name with a quote", "some\"one", false),
        Row("nothing", "", false),
        Row("longer than Steam allows", String(repeating: "a", count: 65), false),
    ]

    @Test(arguments: accountNames)
    func `only an account name Steam could have is ever typed`(row: Row<String, Bool>) {
        #expect(isSteamAccountName(row.input) == row.expected)
        let effects = Self.talk(.signIn(account: row.input), [.console])
        if row.expected {
            #expect(effects == [.type("login \(row.input)"), .report(.signingIn)])
        } else {
            #expect(effects == [.finish(.failure(.notAnAccountName)), .type("quit")])
        }
    }
}
