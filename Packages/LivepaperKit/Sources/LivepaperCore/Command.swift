import Foundation

/// Which displays a transport action or an assignment is for.
public enum DisplayTarget: Hashable, Sendable {
    /// Every display: All Displays for an assignment, Pause All for a pause.
    case all
    case display(DisplayIdentity)
}

/// What a door asks the app to do: the `livepaper://` grammar, shared by the
/// URL scheme, the command socket and the `livepaper` tool (M7).
///
/// `livepaper://<verb>?<key>=<value>`, the verb being the host. Wallpapers and
/// playlists are named by ID, never by path; `file` is a path for the importer
/// alone to read; no verb runs anything. Every door's input becomes one of
/// these, which the app model runs, so that the app stays the only writer.
public enum Command: Hashable, Sendable {
    /// Imports each file through `discoverSources`. With `setEverywhere`, the
    /// one wallpaper that results, new or already there, goes on every display
    /// (`wallpaperToSetEverywhere(resulting:)`).
    case `import`([URL], setEverywhere: Bool)
    /// Assigns a wallpaper or a playlist. An ID the library does not hold is the app's to refuse.
    case set(Assignment, on: DisplayTarget)
    case pause(DisplayTarget)
    case resume(DisplayTarget)
    /// Moves on the playlist a display shows; a display showing a wallpaper is left as it is.
    case next(DisplayTarget)
    case mute
    case unmute
    /// Opens the library window.
    case library
    case settings
    /// The diagnostics report: on the clipboard from the scheme, in the reply from the socket.
    case diagnostics
    /// Host status, displays, the library's IDs and names, pause and mute. Socket only.
    case status

    /// The URL's host.
    public enum Verb: String, CaseIterable, Sendable {
        case `import`, set, pause, resume, next, mute, unmute, library, settings, diagnostics, status

        /// The keys the verb takes; any other is a rejection.
        var keys: Set<String> {
            switch self {
            case .import: [Key.file, Key.set]
            case .set: [Key.wallpaper, Key.playlist, Key.display]
            case .pause, .resume, .next: [Key.display]
            case .mute, .unmute, .library, .settings, .diagnostics, .status: []
            }
        }
    }

    public static let scheme = "livepaper"

    public var verb: Verb {
        switch self {
        case .import: .import
        case .set: .set
        case .pause: .pause
        case .resume: .resume
        case .next: .next
        case .mute: .mute
        case .unmute: .unmute
        case .library: .library
        case .settings: .settings
        case .diagnostics: .diagnostics
        case .status: .status
        }
    }
}

// MARK: - Rendering

extension Command {
    /// The command as its URL, keys in the grammar's order. `display=all` is the
    /// default, so it is left out. Parsing the URL gives this command back.
    public var url: URL {
        var string = "\(Self.scheme)://\(verb.rawValue)"
        let query = queryItems.map { "\($0.key)=\(Self.escaped($0.value))" }
        if !query.isEmpty { string += "?" + query.joined(separator: "&") }
        guard let url = URL(string: string) else { preconditionFailure("a rendered command is a URL: \(string)") }
        return url
    }

    private var queryItems: [(key: String, value: String)] {
        switch self {
        case .import(let files, let setEverywhere):
            files.map { (Key.file, $0.path(percentEncoded: false)) } + (setEverywhere ? [(Key.set, Key.all)] : [])
        case .set(let assignment, let target):
            [Self.item(for: assignment)] + Self.items(for: target)
        case .pause(let target), .resume(let target), .next(let target):
            Self.items(for: target)
        case .mute, .unmute, .library, .settings, .diagnostics, .status:
            []
        }
    }

    private static func item(for assignment: Assignment) -> (key: String, value: String) {
        switch assignment {
        case .wallpaper(let id): (Key.wallpaper, id.description)
        case .playlist(let id): (Key.playlist, id.description)
        }
    }

    private static func items(for target: DisplayTarget) -> [(key: String, value: String)] {
        switch target {
        case .all: []
        case .display(let display): [(Key.display, display.description)]
        }
    }

    /// Everything but the unreserved characters and `/` is escaped, so that a
    /// name holding `&`, `=`, `+` or `#` cannot end its value early.
    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueCharacters) ?? value
    }

    private static let queryValueCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"
    )
}

// MARK: - Parsing

extension Command {
    /// A command from any door that hands over a URL: the scheme, or the socket's request line.
    public init(url: URL) throws(CommandRejection) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw .notLivepaper }
        try self.init(components: components)
    }

    /// A command from the socket's request line, which is the command's URL.
    public init(string: String) throws(CommandRejection) {
        guard let components = URLComponents(string: string) else { throw .notLivepaper }
        try self.init(components: components)
    }

    private init(components: URLComponents) throws(CommandRejection) {
        guard components.scheme?.lowercased() == Self.scheme else { throw .notLivepaper }
        guard components.user == nil, components.password == nil else { throw .credentials }
        guard components.port == nil else { throw .port }
        guard components.percentEncodedPath.isEmpty else { throw .path(components.percentEncodedPath) }
        guard components.fragment == nil else { throw .fragment }
        guard let host = components.percentEncodedHost, !host.isEmpty else { throw .noVerb }
        guard let verb = Verb(rawValue: host) else { throw .unknownVerb(host) }

        var query = Query(verb: verb)
        for item in components.queryItems ?? [] {
            try query.add(item)
        }
        self = try query.command()
    }
}

private enum Key {
    static let file = "file"
    static let set = "set"
    static let wallpaper = "wallpaper"
    static let playlist = "playlist"
    static let display = "display"
    static let all = "all"
}

/// The query's items, gathered by key and checked against the verb.
private struct Query {
    let verb: Command.Verb
    private var values: [String: [String]] = [:]

    init(verb: Command.Verb) {
        self.verb = verb
    }

    mutating func add(_ item: URLQueryItem) throws(CommandRejection) {
        guard verb.keys.contains(item.name) else { throw .unknownKey(verb: verb, key: item.name) }
        // Only `file` may repeat.
        if item.name != Key.file, values[item.name] != nil { throw .repeatedKey(item.name) }
        values[item.name, default: []].append(item.value ?? "")
    }

    func command() throws(CommandRejection) -> Command {
        switch verb {
        case .import: return .import(try files(), setEverywhere: try setEverywhere())
        case .set: return .set(try assignment(), on: try target())
        case .pause, .resume, .next: return try transport()
        case .mute: return .mute
        case .unmute: return .unmute
        case .library: return .library
        case .settings: return .settings
        case .diagnostics: return .diagnostics
        case .status: return .status
        }
    }

    /// Pause, resume or next, on the displays the query names.
    private func transport() throws(CommandRejection) -> Command {
        let target = try target()
        return verb == .pause ? .pause(target) : verb == .resume ? .resume(target) : .next(target)
    }

    private func files() throws(CommandRejection) -> [URL] {
        let files = try (values[Key.file] ?? []).map { path throws(CommandRejection) in try Self.file(path) }
        guard !files.isEmpty else { throw .missingKey(verb: verb, key: Key.file) }
        return files
    }

    private static func file(_ path: String) throws(CommandRejection) -> URL {
        guard !path.isEmpty else { throw .emptyFile }
        guard path.hasPrefix("/") else { throw .relativeFile(path) }
        guard !path.contains("\u{0}") else { throw .invalidValue(key: Key.file, value: path) }
        return URL(filePath: path)
    }

    private func setEverywhere() throws(CommandRejection) -> Bool {
        guard let value = values[Key.set]?.first else { return false }
        guard value == Key.all else { throw .invalidValue(key: Key.set, value: value) }
        return true
    }

    private func assignment() throws(CommandRejection) -> Assignment {
        switch (values[Key.wallpaper]?.first, values[Key.playlist]?.first) {
        case (let wallpaper?, nil): .wallpaper(WallpaperID(uuid: try Self.uuid(wallpaper, key: Key.wallpaper)))
        case (nil, let playlist?): .playlist(PlaylistID(uuid: try Self.uuid(playlist, key: Key.playlist)))
        default: throw .needsWallpaperOrPlaylist
        }
    }

    private func target() throws(CommandRejection) -> DisplayTarget {
        guard let value = values[Key.display]?.first, value != Key.all else { return .all }
        return .display(DisplayIdentity(uuid: try Self.uuid(value, key: Key.display)))
    }

    private static func uuid(_ value: String, key: String) throws(CommandRejection) -> UUID {
        guard let uuid = UUID(uuidString: value) else { throw .notAUUID(key: key, value: value) }
        return uuid
    }
}

// MARK: - Rejections

/// Why a URL is not a command. The app logs `reason`, and the socket replies with it.
public enum CommandRejection: Error, Hashable, Sendable, CustomStringConvertible {
    /// Not a URL, or not a `livepaper:` one.
    case notLivepaper
    case noVerb
    case unknownVerb(String)
    case path(String)
    case fragment
    case port
    /// A user name or a password.
    case credentials
    case unknownKey(verb: Command.Verb, key: String)
    /// A key given twice where it may be given once: any but `file`.
    case repeatedKey(String)
    case missingKey(verb: Command.Verb, key: String)
    /// `set` names one wallpaper or one playlist: not neither, not both.
    case needsWallpaperOrPlaylist
    case emptyFile
    /// A `file` that is not an absolute path.
    case relativeFile(String)
    case notAUUID(key: String, value: String)
    case invalidValue(key: String, value: String)
    /// A command this door does not take: `status` through the scheme.
    case notThroughThisDoor(Command.Verb)

    /// The reason in a sentence. What the sender wrote is repeated in part only,
    /// since anything, a web page included, can open the scheme.
    public var reason: String {
        switch self {
        case .notLivepaper: "It is not a livepaper:// command"
        case .noVerb: "The command names no verb"
        case .unknownVerb(let verb): "“\(Self.quoted(verb))” is not a Livepaper command"
        case .path(let path): "A command has no path, and this one has “\(Self.quoted(path))”"
        case .fragment: "A command has no fragment"
        case .port: "A command has no port"
        case .credentials: "A command has no user name or password"
        case .unknownKey(let verb, let key): "“\(verb.rawValue)” does not take “\(Self.quoted(key))”"
        case .repeatedKey(let key): "“\(key)” is given more than once"
        case .missingKey(let verb, let key): "“\(verb.rawValue)” needs a “\(key)”"
        case .needsWallpaperOrPlaylist: "“set” names one wallpaper or one playlist"
        case .emptyFile: "A “file” is empty"
        case .relativeFile(let path): "A “file” must be an absolute path, not “\(Self.quoted(path))”"
        case .notAUUID(let key, let value): "“\(key)” must be a UUID\(key == "display" ? " or “all”" : ""), not “\(Self.quoted(value))”"
        case .invalidValue(let key, let value): "“\(key)” cannot be “\(Self.quoted(value))”"
        case .notThroughThisDoor(let verb): "“\(verb.rawValue)” is answered over the command socket only"
        }
    }

    public var description: String { reason }

    /// At most 40 characters of it, with no line breaks or NULs, so that one log line stays one line.
    private static func quoted(_ value: String) -> String {
        let limit = 40
        let clean = String(value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? "?" : Character($0) })
        return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
    }
}
