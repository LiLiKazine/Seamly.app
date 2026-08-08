import CoreGraphics
import Foundation
@testable import StitchKit

/// Runs frames through the pipeline the app actually ships: the real `ScrollCaptureDriver` picks
/// keyframes, then `BatchStitcher` derives the manifest — the same two steps as `SampleHandler`
/// followed by `StitchAssembler.resolveGeometry`, minus ReplayKit and disk.
///
/// **One implementation, deliberately.** Three suites used to keep private `buildSession` copies
/// built on `PositionTracker` + `FrameSelector`, each labelled a "faithful mirror of SampleHandler's
/// capture → session pipeline". That stopped being true when capture moved to
/// `ScrollCaptureDriver`/`KeyframeSelector`: the extension no longer tracks absolute position or
/// builds seams and bands live, so those helpers were validating a pipeline the app had already
/// stopped shipping — and nothing failed to say so. Anything asserting on capture→stitch behaviour
/// goes through here now.
///
/// The division of labour this models is the real one: the extension's only job is to bank
/// overlapping keyframes, and *all* geometry (order, seams, segment breaks, content bands) is
/// re-derived off-device by `BatchStitcher` at import.
enum CaptureHarness {

    /// A finished capture, ready to composite.
    struct Capture {
        /// Manifest with `BatchStitcher`-derived order, seams, segment breaks and content bands.
        let session: StitchSession
        /// Keyframe images keyed by `Keyframe.index` (scroll-order slot), for `Compositor`.
        let images: [Int: CGImage]

        /// Composite through the same compositor configuration the app uses.
        func composite() throws -> CGImage {
            try Compositor(refinementDelta: 16).composite(session) { images[$0.index]! }
        }
    }

    /// Feed a frame *stream* through the real picker, then assemble what it banked. Use this when
    /// the input models what ReplayKit delivers (many frames, small scroll steps).
    static func capture(
        _ frames: [CGImage],
        order: BatchStitcher.OrderStrategy = .recover,
        driver: ScrollCaptureDriver = ScrollCaptureDriver(),
        stitcher: BatchStitcher = BatchStitcher()
    ) throws -> Capture {
        var driver = driver
        var picked: [CGImage] = []
        for frame in frames {
            if let keyframe = driver.ingest(frame).keyframe { picked.append(keyframe.image) }
        }
        if let tail = driver.finish() { picked.append(tail.image) }
        return try assemble(picked, order: order, stitcher: stitcher)
    }

    /// Assemble frames that are *already* committed keyframes — a fixture set pulled off a device,
    /// or `CaptureSimulator`/`VideoKeyframeSource` output. Skips the picking step rather than
    /// re-running it over sparse input.
    static func assemble(
        _ keyframes: [CGImage],
        order: BatchStitcher.OrderStrategy = .recover,
        stitcher: BatchStitcher = BatchStitcher()
    ) throws -> Capture {
        let plan = try stitcher.plan(keyframes, strategy: order)
        let first = keyframes[plan.order[0]]
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: first.width > first.height ? .landscape : .portrait
        )
        // `plan.session` already carries slot-indexed keyframes plus the derived geometry; this is
        // the same assignment `StitchAssembler.resolveGeometry` makes onto the stored manifest.
        session.keyframes = plan.session.keyframes
        session.seams = plan.session.seams
        session.segmentBreaks = plan.session.segmentBreaks
        session.contentBands = plan.session.contentBands
        session.orderAssumed = plan.session.orderAssumed

        var images: [Int: CGImage] = [:]
        for (slot, source) in plan.order.enumerated() { images[slot] = keyframes[source] }
        return Capture(session: session, images: images)
    }
}
