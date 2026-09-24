import Foundation
import SceneItemFormat
import simd

/// A particle system simulated on the CPU: the emitters, initializers, operators and renderers the seven
/// scenes use. What each parameter means is read off the presets' values; none of it is checked against
/// Wallpaper Engine, so motion is plausible rather than exact.
final class ParticleSystem {
    struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float> = .zero
        var age: Float = 0
        var life: Float = 1
        var size: Float = 20
        var color: SIMD3<Float> = .one
        var alpha: Float = 1
        var rotation: Float = 0
        var angular: Float = 0
        var oscFreq: Float = 0
        var oscPhase: Float = 0
        var oscScale: Float = 0
        var alphaFreq: Float = 0
        var alphaDepth: Float = 0
        var seed: Float = 0
    }

    static let understood: Set<String> = [
        "sphererandom", "boxrandom", "lifetimerandom", "sizerandom", "colorrandom", "alpharandom", "velocityrandom",
        "rotationrandom", "angularvelocityrandom", "turbulentvelocityrandom", "movement", "alphafade", "alphachange",
        "sizechange", "oscillatealpha", "oscillateposition", "angularmovement", "turbulence", "controlpointattract",
        "sprite", "spritetrail", "ropetrail",
    ]

    let def: ParticleDefinition
    let maxCount: Int
    let rateScale, sizeScale, alphaScale, lifeScale, speedScale: Float
    let tint: SIMD3<Float>
    /// Emits continuously (false: only in bursts, for "eventspawn" children).
    let emits: Bool
    private(set) var particles: [Particle] = []
    /// Where particles died in the last step (for "eventspawn" children).
    private(set) var deaths: [SIMD3<Float>] = []
    private var emitAccumulator: Float = 0
    private var simulated: Float = -1
    private var rng: UInt64

    init(_ def: ParticleDefinition, overrides: [String: Any], scale: Float = 1, maxCount: Int? = nil, emits: Bool = true, seed: UInt64) {
        self.def = def
        self.maxCount = Int(Float(maxCount ?? def.maxCount) * JSONValue.float(overrides["count"], 1))
        rateScale = JSONValue.float(overrides["rate"], 1)
        sizeScale = JSONValue.float(overrides["size"], 1) * scale
        alphaScale = JSONValue.float(overrides["alpha"], 1)
        lifeScale = JSONValue.float(overrides["lifetime"], 1)
        speedScale = JSONValue.float(overrides["speed"], 1) * scale
        tint = JSONValue.vec3(overrides["colorn"], .one)
        self.emits = emits
        rng = seed | 1
    }

    var unsupported: [String] {
        (def.emitters + def.initializers + def.operators + def.renderers).map(\.name).filter { !Self.understood.contains($0) }
    }

    private func random() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        return Float(rng >> 40) / Float(1 << 24)
    }

    private func between(_ a: Float, _ b: Float) -> Float { a + (b - a) * random() }

    private func between(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(between(a.x, b.x), between(a.y, b.y), between(a.z, b.z))
    }

    func spawn(at position: SIMD3<Float>? = nil) {
        guard particles.count < maxCount else { return }
        var p = Particle(position: position ?? .zero, seed: random())
        if let e = def.emitters.first {
            let origin = e.vec3("origin", .zero)
            var direction = SIMD3<Float>.zero
            if e.name == "boxrandom" {
                let half = e.vec3("distancemax", SIMD3(128, 128, 0))
                if position == nil { p.position = origin + SIMD3(random() * 2 - 1, random() * 2 - 1, 0) * half }
            } else {
                let dirs = e.vec3("directions", SIMD3(1, 1, 0))
                let angle = random() * 2 * .pi
                direction = SIMD3(cos(angle), sin(angle), 0) * dirs
                let distance = between(e.float("distancemin", 0), e.float("distancemax", 256))
                if position == nil { p.position = origin + direction * distance }
            }
            let speed = between(e.float("speedmin", 0), e.float("speedmax", 0))
            if speed != 0, simd_length(direction) > 0 { p.velocity = simd_normalize(direction) * speed }
        }
        if let c = def.initializer("lifetimerandom") { p.life = between(c.float("min", 1), c.float("max", 1)) }
        p.life *= lifeScale
        if let c = def.initializer("sizerandom") { p.size = between(c.float("min", 20), c.float("max", 20)) }
        p.size *= sizeScale
        if let c = def.initializer("colorrandom") {
            p.color = (c.vec3("min", SIMD3(repeating: 255)) + (c.vec3("max", SIMD3(repeating: 255)) - c.vec3("min", SIMD3(repeating: 255))) * random()) / 255
        }
        p.color *= tint
        if let c = def.initializer("alpharandom") { p.alpha = between(c.float("min", 0), c.float("max", 1)) }
        p.alpha *= alphaScale
        if let c = def.initializer("velocityrandom") { p.velocity += between(c.vec3("min", .zero), c.vec3("max", .zero)) }
        if let c = def.initializer("turbulentvelocityrandom") {
            let speed = between(c.float("speedmin", 50), c.float("speedmax", 100))
            let angle = random() * 2 * .pi
            p.velocity += SIMD3(cos(angle), sin(angle), 0) * speed
        }
        p.velocity *= speedScale
        p.velocity.z = 0
        if let c = def.initializer("rotationrandom") {
            p.rotation = between(c.vec3("min", .zero).z, c.vec3("max", SIMD3(0, 0, 2 * .pi)).z)
        }
        if let c = def.initializer("angularvelocityrandom") { p.angular = between(c.vec3("min", .zero).z, c.vec3("max", .zero).z) }
        if let o = def.op("oscillateposition") {
            p.oscFreq = between(o.float("frequencymin", 0), o.float("frequencymax", 1))
            p.oscScale = between(o.float("scalemin", 0), o.float("scalemax", 10))
            p.oscPhase = between(o.float("phasemin", 0), o.float("phasemax", 2 * .pi))
        }
        if let o = def.op("oscillatealpha") {
            p.alphaFreq = between(o.float("frequencymin", 0), o.float("frequencymax", 1))
            p.alphaDepth = between(o.float("scalemin", 0), o.float("scalemax", 1))
        }
        particles.append(p)
    }

    func step(_ dt: Float) {
        deaths = []
        if emits, let e = def.emitters.first {
            emitAccumulator += e.float("rate", 5) * rateScale * dt
            while emitAccumulator >= 1 {
                emitAccumulator -= 1
                spawn()
            }
        }
        let movement = def.op("movement")
        let gravity = movement?.vec3("gravity", .zero) ?? .zero
        let drag = movement?.float("drag", 0) ?? 0
        let turbulence = def.op("turbulence")
        let angularForce = def.op("angularmovement")?.vec3("force", .zero).z ?? 0
        // Control points with no flags sit at the system's origin plus their offset; flagged ones follow the
        // pointer, which a wallpaper does not have.
        let attract = def.op("controlpointattract")
        let point = attract.flatMap { a in
            def.controlPoints.first { $0.id == Int(a.float("controlpoint", 0)) && $0.flags == 0 }?.offset
        }
        for i in particles.indices {
            var p = particles[i]
            p.age += dt
            if movement != nil {
                p.velocity += gravity * dt
                p.velocity *= max(0, 1 - drag * dt)
            }
            if let t = turbulence {
                let scale = t.float("scale", 0.005), speed = t.float("speedmax", 100)
                let n = SIMD3(sin(p.position.y * scale * 6.28 + p.seed * 20 + p.age),
                              cos(p.position.x * scale * 6.28 + p.seed * 13 + p.age), 0)
                p.velocity += n * t.vec3("mask", SIMD3(1, 1, 0)) * speed * dt
            }
            if let a = attract, let point {
                let d = point - p.position
                let dist = simd_length(d)
                if dist > 0.001, dist < a.float("threshold", 512) { p.velocity += d / dist * a.float("scale", 100) * dt }
            }
            p.angular += angularForce * dt
            p.rotation += p.angular * dt
            p.position += p.velocity * dt
            particles[i] = p
        }
        deaths = particles.filter { $0.age >= $0.life }.map(\.position)
        particles.removeAll { $0.age >= $0.life }
    }

    /// Simulates up to `time`: from the preset's warm-up (`starttime`) on first use or if time went back.
    func advance(to time: Float, child: ((ParticleSystem) -> Void)? = nil) {
        if simulated < 0 || time < simulated {
            particles = []
            emitAccumulator = 0
            var t = -def.startTime
            while t < time {
                step(1 / 30)
                child?(self)
                t += 1 / 30
            }
            simulated = time
            return
        }
        var dt = time - simulated
        while dt > 0 {
            let s = min(dt, 1 / 30)
            step(s)
            child?(self)
            dt -= s
        }
        simulated = time
    }

    /// Two triangles per particle: position (xyz), uv, colour (rgba), in the system's own space.
    func vertices() -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(particles.count * 54)
        let fade = def.op("alphafade")
        let fadeIn = fade?.float("fadeintime", 0.5) ?? 0, fadeOut = fade?.float("fadeouttime", 0.5) ?? 1
        let alphaChange = def.op("alphachange")
        let sizeChange = def.op("sizechange")
        let mask = def.op("oscillateposition")?.vec3("mask", SIMD3(1, 1, 0)) ?? .zero
        let trail = def.renderers.first { $0.name == "spritetrail" || $0.name == "ropetrail" }
        for p in particles {
            let f = p.age / max(p.life, 1e-4)
            var alpha = p.alpha
            if fade != nil {
                if f < fadeIn { alpha *= f / max(fadeIn, 1e-4) }
                if f > fadeOut { alpha *= max(0, (1 - f) / max(1 - fadeOut, 1e-4)) }
            }
            if let a = alphaChange {
                let t0 = a.float("starttime", 0), t1 = a.float("endtime", 1)
                let k = min(1, max(0, (f - t0) / max(t1 - t0, 1e-4)))
                alpha *= a.float("startvalue", 1) + (a.float("endvalue", 0) - a.float("startvalue", 1)) * k
            }
            if p.alphaFreq > 0 { alpha *= 1 - p.alphaDepth * (0.5 + 0.5 * sin(p.age * p.alphaFreq * 2 * .pi + p.seed * 6.28)) }
            var size = p.size
            if let s = sizeChange {
                let t0 = s.float("starttime", 0), t1 = s.float("endtime", 1)
                let k = min(1, max(0, (f - t0) / max(t1 - t0, 1e-4)))
                size *= s.float("startvalue", 1) + (s.float("endvalue", 0) - s.float("startvalue", 1)) * k
            }
            var pos = p.position
            if p.oscScale > 0 {
                let phase = p.age * p.oscFreq * 2 * .pi + p.oscPhase
                pos += mask * SIMD3(sin(phase), cos(phase), 0) * p.oscScale
            }
            // A sprite is a square turned by its rotation; a trail is stretched along the velocity.
            var ax = SIMD2<Float>(cos(p.rotation), sin(p.rotation)) * size / 2
            var ay = SIMD2<Float>(-sin(p.rotation), cos(p.rotation)) * size / 2
            if let trail {
                let v = SIMD2(p.velocity.x, p.velocity.y)
                let speed = simd_length(v)
                if speed > 0.001 {
                    let length = min(speed * trail.float("length", 0.05) * 100, trail.float("maxlength", 1000))
                    ay = v / speed * max(size, length) / 2
                    ax = SIMD2(-ay.y, ay.x) / max(simd_length(ay), 1e-4) * size / 2
                }
            }
            let corners: [(SIMD2<Float>, SIMD2<Float>)] = [(-ax + ay, SIMD2(0, 0)), (ax + ay, SIMD2(1, 0)), (-ax - ay, SIMD2(0, 1)),
                                                           (ax + ay, SIMD2(1, 0)), (ax - ay, SIMD2(1, 1)), (-ax - ay, SIMD2(0, 1))]
            for (d, uv) in corners {
                out += [pos.x + d.x, pos.y + d.y, 0, uv.x, uv.y, p.color.x, p.color.y, p.color.z, max(0, alpha)]
            }
        }
        return out
    }
}
