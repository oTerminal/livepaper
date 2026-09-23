import Foundation

/// A Wallpaper Engine `.pkg`: u32 length + "PKGV00xx", u32 entry count, per entry (u32 name length, name,
/// u32 offset, u32 size), then the files back to back. Offsets count from the end of the table.
public struct PkgArchive: Sendable {
    public let version: String
    public let entries: [String: Range<Int>]
    /// Entry names in table order.
    public let order: [String]
    let data: Data

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        var reader = ByteReader(data)
        version = try reader.lengthPrefixedString()
        guard version.hasPrefix("PKGV") else { throw ReadError("not a pkg: \(version)") }
        let count = try reader.int()
        var table: [(String, Int, Int)] = []
        for _ in 0..<count {
            let name = try reader.lengthPrefixedString()
            let offset = try reader.int()
            let size = try reader.int()
            table.append((name, offset, size))
        }
        let base = reader.offset
        var entries: [String: Range<Int>] = [:]
        for (name, offset, size) in table {
            let range = (base + offset)..<(base + offset + size)
            guard range.upperBound <= data.count else { throw ReadError("\(name) runs past the end") }
            entries[name] = range
        }
        self.entries = entries
        self.order = table.map(\.0)
        self.data = data
    }

    public func file(_ path: String) -> Data? {
        guard let range = entries[path] else { return nil }
        return data.subdata(in: range)
    }
}

/// The files of one Workshop item: the pkg's entries first, then loose files beside it.
public struct ItemFiles: Sendable {
    public let folder: URL
    public let pkg: PkgArchive?

    public init(folder: URL) throws {
        self.folder = folder
        let pkgs = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
            .filter { $0.hasSuffix(".pkg") }.sorted() ?? []
        pkg = try pkgs.first.map { try PkgArchive(url: folder.appendingPathComponent($0)) }
    }

    public func data(_ path: String) -> Data? {
        if let data = pkg?.file(path) { return data }
        return try? Data(contentsOf: folder.appendingPathComponent(path))
    }

    public func contains(_ path: String) -> Bool {
        pkg?.entries[path] != nil || FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path)
    }

    public func json(_ path: String) throws -> [String: Any] {
        guard let data = data(path) else { throw ReadError("missing \(path)") }
        guard let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw ReadError("\(path) is not an object")
        }
        return object
    }

    public func text(_ path: String) -> String? {
        data(path).map { String(decoding: $0, as: UTF8.self) }
    }
}
