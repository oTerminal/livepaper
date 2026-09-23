/// std140 layout of the one uniform block the translator gives each stage (every loose `uniform` that is
/// not a sampler, in declaration order).
public struct UniformLayout: Codable, Sendable {
    public struct Member: Codable, Sendable {
        public let name: String
        public let type: String
        public let arrayCount: Int?
        public let offset: Int
        /// Array element stride (16 for every std140 array of scalars or vectors).
        public let stride: Int
    }

    public var members: [Member] = []
    public var size: Int = 16

    public init() {}

    static func std140(_ decls: [(type: String, name: String, count: Int?)]) -> UniformLayout {
        var layout = UniformLayout()
        var offset = 0
        for d in decls {
            let (align, size) = alignSize(d.type)
            var a = align, stride = size
            if d.count != nil {
                a = 16
                stride = (size + 15) / 16 * 16
            }
            offset = (offset + a - 1) / a * a
            layout.members.append(Member(name: d.name, type: d.type, arrayCount: d.count, offset: offset, stride: stride))
            offset += d.count.map { $0 * stride } ?? size
        }
        layout.size = max(16, (offset + 15) / 16 * 16)
        return layout
    }

    static func alignSize(_ type: String) -> (Int, Int) {
        switch type {
        case "float", "int", "uint", "bool": (4, 4)
        case "vec2", "ivec2", "uvec2", "bvec2": (8, 8)
        case "vec3", "ivec3", "uvec3", "bvec3": (16, 12)
        case "vec4", "ivec4", "uvec4", "bvec4": (16, 16)
        case "mat2": (16, 32)
        case "mat3": (16, 48)
        case "mat4": (16, 64)
        default: (16, 16)
        }
    }

    public func member(_ name: String) -> Member? { members.first { $0.name == name } }

    /// Packs `values` (floats; ints are converted) for each member that has one; the rest stay zero.
    /// A single value given for a vector fills every component.
    public func pack(_ value: (Member) -> [Float]?) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        for m in members {
            guard let values = value(m) else { continue }
            let isInt = m.type.hasPrefix("int") || m.type.hasPrefix("ivec") || m.type == "bool"
            func put(_ v: Float, _ offset: Int) {
                guard offset + 4 <= bytes.count else { return }
                let bits = isInt ? UInt32(bitPattern: Int32(v)) : v.bitPattern
                for i in 0..<4 { bytes[offset + i] = UInt8((bits >> (8 * UInt32(i))) & 0xff) }
            }
            let components: Int = switch m.type {
            case "vec2", "ivec2": 2
            case "vec3", "ivec3": 3
            case "vec4", "ivec4": 4
            default: 1
            }
            switch m.type {
            case "mat4":
                for (i, v) in values.prefix(16 * (m.arrayCount ?? 1)).enumerated() { put(v, m.offset + i * 4) }
            case "mat3":
                // Accepts 9 values (column-major 3x3) or 16 (a mat4's columns).
                for c in 0..<3 {
                    for r in 0..<3 {
                        let i = values.count == 9 ? c * 3 + r : c * 4 + r
                        if i < values.count { put(values[i], m.offset + c * 16 + r * 4) }
                    }
                }
            default:
                if let count = m.arrayCount {
                    for e in 0..<count {
                        for c in 0..<components where e * components + c < values.count {
                            put(values[e * components + c], m.offset + e * m.stride + c * 4)
                        }
                    }
                } else {
                    for c in 0..<components {
                        put(values.count == 1 ? values[0] : (c < values.count ? values[c] : 0), m.offset + c * 4)
                    }
                }
            }
        }
        return bytes
    }
}
