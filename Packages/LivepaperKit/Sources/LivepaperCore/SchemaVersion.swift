import Foundation

/// The version every persisted file carries.
///
/// A minor version only adds fields, which an older reader ignores and a newer
/// reader defaults. A major version changes meaning: a reader that does not
/// know it refuses the file rather than guess.
public struct SchemaVersion: Codable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public var description: String { "\(major).\(minor)" }
}

public enum SchemaError: Error, Equatable, Sendable {
    /// The file was written by a schema this build does not know. Nothing is read from it.
    case unsupportedVersion(SchemaVersion)
}

/// JSON as Livepaper's files are written: stable key order so that the same
/// value gives the same bytes, and dates a person can read.
enum PersistedJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(withMilliseconds))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: withMilliseconds) ?? Date(text, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date: \(text)"))
        }
        return decoder
    }

    private static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
