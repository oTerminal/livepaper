import Testing
@testable import LivepaperPlayback

struct CrossfadePlanTests {
    struct Request: Sendable {
        var front: VideoSlot?
        var incoming: VideoSlot?
        var crossfade: Bool
    }

    static let rows: [Row<Request, CrossfadePlan>] = [
        Row(
            "with nothing showing the lower layer starts, opaque once it has a picture, without a fade",
            Request(front: nil, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.lower),
                before: [OpacityChange(.upper, 0)],
                whenReady: [OpacityChange(.lower, 1)],
                front: .lower
            )
        ),
        Row(
            "with nothing showing and no crossfade asked the same",
            Request(front: nil, incoming: nil, crossfade: false),
            CrossfadePlan(
                start: .fresh(.lower),
                before: [OpacityChange(.upper, 0)],
                whenReady: [OpacityChange(.lower, 1)],
                front: .lower
            )
        ),
        Row(
            "a request while the first engine is still starting redirects it",
            Request(front: nil, incoming: .lower, crossfade: true),
            CrossfadePlan(start: .redirect(.lower), front: .lower)
        ),
        Row(
            "a new video over the lower layer fades in on the upper one",
            Request(front: .lower, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.upper),
                before: [OpacityChange(.upper, 0)],
                fade: OpacityChange(.upper, 1),
                front: .upper,
                stops: .lower
            )
        ),
        Row(
            "a new video under the upper layer starts there, and the upper one fades out",
            Request(front: .upper, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.lower),
                before: [OpacityChange(.lower, 1)],
                fade: OpacityChange(.upper, 0),
                front: .lower,
                stops: .upper
            )
        ),
        Row(
            "without a crossfade the lower layer switches in place",
            Request(front: .lower, incoming: nil, crossfade: false),
            CrossfadePlan(start: .inPlace(.lower), front: .lower)
        ),
        Row(
            "without a crossfade the upper layer switches in place",
            Request(front: .upper, incoming: nil, crossfade: false),
            CrossfadePlan(start: .inPlace(.upper), front: .upper)
        ),
        Row(
            "a request during a crossfade waits for it to end",
            Request(front: .lower, incoming: .upper, crossfade: true),
            CrossfadePlan(start: .afterCrossfade, front: .lower)
        ),
        Row(
            "a request during a crossfade back waits for it too, crossfade or not",
            Request(front: .upper, incoming: .lower, crossfade: false),
            CrossfadePlan(start: .afterCrossfade, front: .upper)
        ),
    ]

    @Test(arguments: rows)
    func `plans the change of video`(row: Row<Request, CrossfadePlan>) {
        let situation = CrossfadeSituation(front: row.input.front, incoming: row.input.incoming)

        let plan = planCrossfade(situation, crossfade: row.input.crossfade)

        #expect(plan == row.expected)
    }

    /// The two layers at rest with a video showing, as a crossfade finds them: the one in front
    /// has a picture; the lower one is opaque once it has played, and an engine that stopped
    /// took its picture with it.
    static let atRest: [Row<VideoSlot, Void>] = [
        Row("from the lower layer", .lower, ()),
        Row("from the upper layer", .upper, ()),
    ]

    @Test(arguments: atRest)
    func `a crossfade always has a fully visible video`(row: Row<VideoSlot, Void>) throws {
        let front = row.input
        var layers = LayerModel(front: front)
        let plan = planCrossfade(CrossfadeSituation(front: front, incoming: nil), crossfade: true)
        guard case .fresh(let starting) = plan.start else {
            Issue.record("a crossfade starts a fresh engine: \(plan)")
            return
        }
        let fade = try #require(plan.fade)

        layers.apply(plan.before)
        layers.lose(starting)
        #expect(layers.showsVideo, "while the new engine starts")

        layers.gain(starting)
        layers.apply(plan.whenReady)
        #expect(layers.showsVideo, "once the new video is ready")

        layers.apply([OpacityChange(fade.slot, (layers[fade.slot].opacity + fade.opacity) / 2)])
        #expect(layers.showsVideo, "halfway through the fade")

        layers.apply([fade])
        #expect(layers.showsVideo, "at the end of the fade")

        if let stops = plan.stops { layers.lose(stops) }
        #expect(layers.showsVideo, "once the old engine stopped")
        #expect(plan.front == starting)
        #expect(layers[starting].opacity == 1)
    }
}

/// What S5's poll looked at: whether some video layer is fully opaque and has a picture.
private struct LayerModel {
    struct Layer {
        var opacity: Float
        var hasPicture: Bool
    }

    private var layers: [VideoSlot: Layer]

    init(front: VideoSlot) {
        layers = switch front {
        case .lower: [.lower: Layer(opacity: 1, hasPicture: true), .upper: Layer(opacity: 0, hasPicture: false)]
        case .upper: [.lower: Layer(opacity: 1, hasPicture: false), .upper: Layer(opacity: 1, hasPicture: true)]
        }
    }

    subscript(slot: VideoSlot) -> Layer { layers[slot] ?? Layer(opacity: 0, hasPicture: false) }

    var showsVideo: Bool { layers.values.contains { $0.opacity >= 1 && $0.hasPicture } }

    mutating func apply(_ changes: [OpacityChange]) {
        for change in changes { layers[change.slot]?.opacity = change.opacity }
    }

    mutating func lose(_ slot: VideoSlot) { layers[slot]?.hasPicture = false }
    mutating func gain(_ slot: VideoSlot) { layers[slot]?.hasPicture = true }
}
