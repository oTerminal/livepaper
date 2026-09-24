import Foundation
import simd

/// A puppet (`models/*.mdl`, "MDLV0023"), as learned from the one sample that has one (Agamemnon):
///
///     "MDLV0023\0" u32 flags, u32, u32, material path (cstring), zero padding
///     u32 flags, u32 vertex bytes, vertices (80 bytes each):
///         f32 position[3], f32 normal[3], f32 tangent[4], u32 bones[4], f32 weights[4], f32 uv[2]
///     u32 index bytes, u16 triangle-list indices
///     part table: u8, u8, u32 table bytes, u32, then (u32 0, u32 first index, u32 index count, u32 part id)
///     "MDLS0004\0" u32 end offset, u32 bone count,
///         per bone: name (cstring), u32 flags, i32 parent, u32 matrix bytes (64), f32 local bind matrix[16], u8
///         then per-bone editor data (not needed to draw)
///     "MDLA0006\0" u32 end offset, u32 animation count,
///         per animation: u32 id, u32, name (cstring), mode (cstring: "mirror", …), f32 fps, u32 length in frames,
///         u32, u32 bone count; per bone: u32, u32 bytes, frames × (f32 position[3], f32 angles[3], f32 scale[3])
///
/// Positions are pixels from the layer's centre, y up; in the bind pose they coincide with the texture
/// layout, and the animation's first frame moves the parts into place.
public struct PuppetModel: Sendable {
    public struct Vertex: Sendable {
        public let position: SIMD3<Float>
        public let bones: SIMD4<UInt32>
        public let weights: SIMD4<Float>
        public let uv: SIMD2<Float>
    }

    public struct Part: Sendable {
        public let firstIndex: Int
        public let indexCount: Int
        public let id: Int
    }

    public struct Bone: Sendable {
        public let parent: Int
        public let bind: simd_float4x4
    }

    public struct Keyframe: Sendable {
        public let position: SIMD3<Float>
        public let angles: SIMD3<Float>
        public let scale: SIMD3<Float>
    }

    public struct Animation: Sendable {
        public let name: String
        /// "mirror" plays forward then backward.
        public let mode: String
        public let fps: Float
        public let length: Int
        /// Per bone, per frame.
        public let tracks: [[Keyframe]]
    }

    public let materialPath: String
    public let vertices: [Vertex]
    public let indices: [UInt16]
    public let parts: [Part]
    public let bones: [Bone]
    public let animations: [Animation]

    public init(data: Data) throws {
        var r = ByteReader(data)
        let magic = try r.magic()
        guard magic.hasPrefix("MDLV") else { throw ReadError("not a puppet: \(magic)") }
        _ = try r.u32()
        _ = try r.u32()
        _ = try r.u32()
        materialPath = try r.cString()
        // Zero padding, then the vertex block's flags word (non-zero) and byte count.
        while r.remaining >= 4, data[data.startIndex + r.offset] == 0 { r.offset += 1 }
        _ = try r.u32()
        let vertexBytes = try r.int()
        guard vertexBytes % 80 == 0 else { throw ReadError("vertex block of \(vertexBytes) bytes is not 80-byte vertices") }
        var vertices: [Vertex] = []
        for _ in 0..<(vertexBytes / 80) {
            let p = SIMD3(try r.f32(), try r.f32(), try r.f32())
            for _ in 0..<7 { _ = try r.f32() }  // normal, tangent
            let b = SIMD4(try r.u32(), try r.u32(), try r.u32(), try r.u32())
            let w = SIMD4(try r.f32(), try r.f32(), try r.f32(), try r.f32())
            let uv = SIMD2(try r.f32(), try r.f32())
            vertices.append(Vertex(position: p, bones: b, weights: w, uv: uv))
        }
        self.vertices = vertices
        let indexBytes = try r.int()
        var indices: [UInt16] = []
        for _ in 0..<(indexBytes / 2) { indices.append(try r.u16()) }
        self.indices = indices

        // Part table: 16-byte records up to the skeleton.
        var parts: [Part] = []
        let skeleton = r
        var s = skeleton
        guard s.seek(to: "MDLS") else { throw ReadError("no skeleton") }
        var t = r
        t.offset = s.offset - 16
        while t.offset >= r.offset {
            var rec = t
            _ = try rec.u32()
            let first = try rec.int(), count = try rec.int(), id = try rec.int()
            guard first >= 0, count > 0, first + count <= indices.count else { break }
            parts.insert(Part(firstIndex: first, indexCount: count, id: id), at: 0)
            if first == 0 { break }
            t.offset -= 16
        }
        self.parts = parts.isEmpty ? [Part(firstIndex: 0, indexCount: indices.count, id: 0)] : parts

        _ = try s.magic()
        _ = try s.u32()
        let boneCount = try s.int()
        var bones: [Bone] = []
        for _ in 0..<boneCount {
            _ = try s.cString()
            _ = try s.u32()
            let parent = try s.int()
            let size = try s.int()
            var m = [Float]()
            for _ in 0..<16 { m.append(try s.f32()) }
            _ = try s.bytes(size - 64)
            _ = try s.u8()
            bones.append(Bone(parent: parent, bind: simd_float4x4(columns: (
                SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))))
        }
        self.bones = bones

        var animations: [Animation] = []
        var a = s
        if a.seek(to: "MDLA") {
            _ = try a.magic()
            _ = try a.u32()
            let count = try a.int()
            for _ in 0..<count {
                _ = try a.u32()
                _ = try a.u32()
                let name = try a.cString()
                let mode = try a.cString()
                let fps = try a.f32()
                let length = try a.int()
                _ = try a.u32()
                let trackCount = try a.int()
                var tracks: [[Keyframe]] = []
                for _ in 0..<trackCount {
                    _ = try a.u32()
                    let bytes = try a.int()
                    var frames: [Keyframe] = []
                    for _ in 0..<(bytes / 36) {
                        frames.append(Keyframe(position: SIMD3(try a.f32(), try a.f32(), try a.f32()),
                                               angles: SIMD3(try a.f32(), try a.f32(), try a.f32()),
                                               scale: SIMD3(try a.f32(), try a.f32(), try a.f32())))
                    }
                    tracks.append(frames)
                }
                animations.append(Animation(name: name, mode: mode, fps: fps, length: length, tracks: tracks))
            }
        }
        self.animations = animations
    }
}
