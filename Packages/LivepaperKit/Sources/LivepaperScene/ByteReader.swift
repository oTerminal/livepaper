import Foundation

/// The little-endian numbers and tagged sections Wallpaper Engine's files are
/// made of, read front to back. Every read is checked against the end of the
/// data, so a file cut short or lying about a length is an error, never a crash.
struct ByteReader {
    struct CutShort: Error {}

    private let data: Data
    private(set) var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    mutating func bytes(_ count: Int) throws(CutShort) -> Data {
        guard count >= 0, count <= data.endIndex - offset else { throw CutShort() }
        defer { offset += count }
        return data[offset..<offset + count]
    }

    mutating func u32() throws(CutShort) -> UInt32 {
        let bytes = try bytes(4)
        return bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func i32() throws(CutShort) -> Int32 {
        Int32(bitPattern: try u32())
    }

    mutating func f32() throws(CutShort) -> Float {
        Float(bitPattern: try u32())
    }

    /// A u32 length, then that many bytes of text.
    mutating func lengthPrefixedString() throws(CutShort) -> String {
        let length = Int(try u32())
        guard let text = String(bytes: try bytes(length), encoding: .utf8) else { throw CutShort() }
        return text
    }

    /// A section's tag: eight ASCII characters and a NUL, such as `TEXV0005`.
    mutating func tag() throws(CutShort) -> String {
        let bytes = try bytes(9)
        guard bytes.last == 0, let text = String(bytes: bytes.dropLast(), encoding: .ascii) else { throw CutShort() }
        return text
    }
}
