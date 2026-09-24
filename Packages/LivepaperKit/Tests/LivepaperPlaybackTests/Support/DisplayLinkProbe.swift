import Foundation
import Metal
import QuartzCore

/// Whether the system calls a Metal display link on this Mac at all. A test
/// that counts a scene's drawn pictures needs it to; CI's virtual Mac was seen
/// never to within the test's window, which the engine reports as withheld.
enum DisplayLinkProbe {
    static let fires: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        let layer = CAMetalLayer()
        layer.device = device
        layer.drawableSize = CGSize(width: 16, height: 16)
        let target = ProbeTarget()
        nonisolated(unsafe) let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = target
        Thread {
            link.add(to: .current, forMode: .default)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
            link.invalidate()
        }.start()
        return target.called.wait(timeout: .now() + 2) == .success
    }()
}

private final class ProbeTarget: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    let called = DispatchSemaphore(value: 0)

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        called.signal()
    }
}
