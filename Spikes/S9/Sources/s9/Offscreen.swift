import CoreGraphics
import Foundation
import ImageIO
import Metal
import SceneImport
import SceneItemRenderer
import UniformTypeIdentifiers

/// Drives `SceneRenderer` the way a display link would, but into an offscreen BGRA texture: one command
/// buffer per frame from our own queue, then a read-back for PNGs and the MP4.
enum Offscreen {
    static func makeTarget(_ device: any MTLDevice, _ w: Int, _ h: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    static func frame(_ renderer: SceneRenderer, _ queue: any MTLCommandQueue, _ target: any MTLTexture,
                      _ readback: any MTLBuffer, time: Double) -> Data {
        let cb = queue.makeCommandBuffer()!
        renderer.draw(into: target, on: cb, at: time)
        let blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: target.width, height: target.height, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: target.width * 4,
                  destinationBytesPerImage: target.width * target.height * 4)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { print("command buffer error: \(e)") }
        return Data(bytes: readback.contents(), count: target.width * target.height * 4)
    }

    static func writePNG(_ bgra: Data, _ w: Int, _ h: Int, to url: URL) {
        let provider = CGDataProvider(data: bgra as CFData)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info,
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Load as the extension would: from the prepared library folder.
    static func load(_ folder: URL, _ device: any MTLDevice, particles: Bool, effects: Bool) throws -> SceneRenderer {
        let r = try SceneRenderer(folder: folder, device: device)
        r.drawsParticles = particles
        r.drawsEffects = effects
        return r
    }

    static func render(folder: URL, device: any MTLDevice, width: Int, height: Int, out: URL,
                       id: String, videoSeconds: Double, particles: Bool, effects: Bool) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let queue = device.makeCommandQueue()!
        let suffix = (particles ? "" : "-noparticles") + (effects ? "" : "-noeffects")
        let renderer = try load(folder, device, particles: particles, effects: effects)
        renderer.resize(width: width, height: height)
        let target = makeTarget(device, width, height)
        let readback = device.makeBuffer(length: width * height * 4, options: .storageModeShared)!
        // Every frame from 0 to 2 s at 30 fps, as the display link would ask; PNGs at 0, 1 and 2 s.
        for i in 0...60 {
            let px = frame(renderer, queue, target, readback, time: Double(i) / 30)
            if i % 30 == 0 {
                writePNG(px, width, height, to: out.appendingPathComponent("\(id)-\(width)x\(height)\(suffix)-t\(i / 30).png"))
            }
        }
        print("layers: \(renderer.drawnLayers.joined(separator: "; "))")
        for n in renderer.notes { print("note: \(n)") }
        guard videoSeconds > 0 else { return }
        // The MP4 at no more than 1920 wide, from a fresh load so it starts at t = 0 with no history.
        var vw = width, vh = height
        if vw > 1920 { vh = vh * 1920 / vw; vw = 1920 }
        vw -= vw % 2
        vh -= vh % 2
        let video = try load(folder, device, particles: particles, effects: effects)
        video.resize(width: vw, height: vh)
        let vtarget = makeTarget(device, vw, vh)
        let vreadback = device.makeBuffer(length: vw * vh * 4, options: .storageModeShared)!
        let mp4 = out.appendingPathComponent("\(id)-\(vw)x\(vh)\(suffix)-\(Int(videoSeconds))s.mp4")
        let ff = Process()
        ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(vw)x\(vh)", "-r", "30",
                        "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", mp4.path]
        let pipe = Pipe()
        ff.standardInput = pipe
        try ff.run()
        for i in 0..<Int(videoSeconds * 30) {
            try pipe.fileHandleForWriting.write(contentsOf: frame(video, queue, vtarget, vreadback, time: Double(i) / 30))
        }
        try pipe.fileHandleForWriting.close()
        ff.waitUntilExit()
        print("wrote \(mp4.lastPathComponent)")
    }
}
