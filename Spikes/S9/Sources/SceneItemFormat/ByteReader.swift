import Foundation

public struct ReadError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Little-endian cursor over a `Data`.
struct ByteReader {
    let data: Data
    var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw ReadError("read past end at \(offset)") }
        let start = data.startIndex + offset
        let value = data[start..<start + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw ReadError("read past end at \(offset)") }
        let start = data.startIndex + offset
        let value = data[start..<start + 2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        offset += 2
        return UInt16(littleEndian: value)
    }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ReadError("read past end at \(offset)") }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func int() throws -> Int { Int(try i32()) }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw ReadError("need \(count) bytes at \(offset), have \(remaining)") }
        let start = data.startIndex + offset
        offset += count
        return data[start..<start + count]
    }

    /// A NUL-terminated string (magics such as "TEXV0005", names).
    mutating func cString(max: Int = 1024) throws -> String {
        let start = data.startIndex + offset
        guard let end = data[start...].prefix(max).firstIndex(of: 0) else {
            throw ReadError("no NUL-terminated string at \(offset)")
        }
        let text = String(decoding: data[start..<end], as: UTF8.self)
        offset += end - start + 1
        return text
    }

    mutating func magic() throws -> String { try cString(max: 17) }

    mutating func lengthPrefixedString() throws -> String {
        let length = try int()
        return String(decoding: try bytes(length), as: UTF8.self)
    }

    /// Moves to the next occurrence of `marker`, returning false if there is none.
    mutating func seek(to marker: String) -> Bool {
        let needle = Data(marker.utf8)
        guard let r = data[(data.startIndex + offset)...].firstRange(of: needle) else { return false }
        offset = r.lowerBound - data.startIndex
        return true
    }
}
