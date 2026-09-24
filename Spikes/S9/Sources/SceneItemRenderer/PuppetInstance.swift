import Foundation
import Metal
import SceneItemFormat
import simd

/// A puppet on the GPU: its mesh, and its bones posed at a time (linear skinning, up to 32 bones).
final class PuppetInstance {
    static let maxBones = 32
    let model: PuppetModel
    let vertices: any MTLBuffer
    let indices: any MTLBuffer
    let indexCount: Int
    let inverseBind: [simd_float4x4]

    init(model: PuppetModel, device: any MTLDevice) throws {
        guard model.bones.count <= Self.maxBones else { throw ReadError("\(model.bones.count) bones; S9 draws up to \(Self.maxBones)") }
        self.model = model
        // Position, UV, bone indices, bone weights (VertexLayout.skinnedStride).
        var v: [Float] = []
        v.reserveCapacity(model.vertices.count * 13)
        for x in model.vertices {
            v += [x.position.x, x.position.y, x.position.z, x.uv.x, x.uv.y,
                  Float(x.bones.x), Float(x.bones.y), Float(x.bones.z), Float(x.bones.w),
                  x.weights.x, x.weights.y, x.weights.z, x.weights.w]
        }
        guard let vb = device.makeBuffer(bytes: v, length: v.count * 4) else { throw ReadError("no vertex buffer") }
        vertices = vb
        // Parts are drawn in file order: in the sample the last part (id 0, the ponytail) lies over the helmet.
        let ordered = model.indices
        guard let ib = device.makeBuffer(bytes: ordered, length: max(2, ordered.count * 2)) else { throw ReadError("no index buffer") }
        indices = ib
        indexCount = ordered.count
        inverseBind = Self.world(model.bones.map(\.bind), parents: model.bones.map(\.parent)).map { $0.inverse }
    }

    static func world(_ local: [simd_float4x4], parents: [Int]) -> [simd_float4x4] {
        var out = local
        for i in out.indices where parents[i] >= 0 && parents[i] < i {
            out[i] = out[parents[i]] * local[i]
        }
        return out
    }

    /// Bone matrices for `g_Bones` at `time`, taking pixel positions to the layer's unit quad.
    func pose(at time: Float, halfSize: SIMD2<Float>) -> [Float] {
        var local = model.bones.map(\.bind)
        if let anim = model.animations.first, anim.length > 0, anim.fps > 0 {
            var frame = time * anim.fps
            let n = Float(anim.length)
            if anim.mode == "mirror" {
                frame = frame.truncatingRemainder(dividingBy: 2 * n)
                if frame > n { frame = 2 * n - frame }
            } else {
                frame = frame.truncatingRemainder(dividingBy: n)
            }
            for (bone, track) in anim.tracks.enumerated() where bone < local.count && !track.isEmpty {
                let i0 = min(track.count - 1, Int(frame)), i1 = min(track.count - 1, i0 + 1)
                let k = frame - Float(i0)
                let a = track[i0], b = track[i1]
                let p = a.position + (b.position - a.position) * k
                let angle = a.angles.z + (b.angles.z - a.angles.z) * k
                let s = a.scale + (b.scale - a.scale) * k
                var m = simd_float4x4(diagonal: SIMD4(s.x, s.y, 1, 1))
                let c = cos(angle), sn = sin(angle)
                m = simd_float4x4(columns: (SIMD4(c, sn, 0, 0), SIMD4(-sn, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))) * m
                m.columns.3 = SIMD4(p.x, p.y, p.z, 1)
                local[bone] = m
            }
        }
        let world = Self.world(local, parents: model.bones.map(\.parent))
        let toUnit = simd_float4x4(diagonal: SIMD4(1 / halfSize.x, 1 / halfSize.y, 1, 1))
        var out: [Float] = []
        for i in 0..<Self.maxBones {
            let m = i < world.count ? toUnit * world[i] * inverseBind[i] : matrix_identity_float4x4
            out += [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
        }
        return out
    }

    var mesh: Mesh { Mesh(vertices: vertices, vertexCount: model.vertices.count, indices: (indices, indexCount)) }
}
