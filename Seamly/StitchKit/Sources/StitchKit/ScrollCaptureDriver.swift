import CoreGraphics
import Foundation

/// The pure, `Sendable` capture loop — the picking parallel to `BatchStitcher`'s assembly.
///
/// `SampleHandler` used to hold this loop inline, tangled with ReplayKit, the App Group, disk
/// writes, and haptics, so none of it could run or be tested off-device. Extracting it here lets
/// the synthetic and video test tiers drive the *real production picking code* against real
/// frames. This type profiles each frame, asks `KeyframeSelector` whether to bank it, decides the
/// safety cue (overlap below `safetyMargin`), builds the `Keyframe` metadata, and — at
/// `finish()` — banks the trailing frame if there is still uncommitted downward motion.
///
/// It does NOT touch ReplayKit, disk, or haptics: the adapter (`SampleHandler`) writes the
/// returned image's bytes, appends the metadata to the manifest, throttles + plays the cue, and
/// maps the first keyframe's image to the session's orientation/color space. This extraction is
/// behaviour-preserving for every *commit decision* — the same frames get banked at the same
/// points. One intentional divergence: `keyframeIndex` numbering (see below) can leave a gap on
/// a write failure, where the old inline code reused the number on the next attempt instead.
public struct ScrollCaptureDriver: Sendable {

    /// One committed keyframe: the image whose bytes the adapter writes, plus its manifest entry.
    public struct CapturedKeyframe: Sendable {
        public let image: CGImage
        public let metadata: Keyframe
    }

    /// The outcome of ingesting one frame: a keyframe to commit (or `nil`), and whether the
    /// adapter should fire the safety cue for this frame.
    public struct Step: Sendable {
        public let keyframe: CapturedKeyframe?
        public let fireSafetyCue: Bool
    }

    private let profiler: VerticalProfile
    private var selector: KeyframeSelector
    /// Overlap fraction with the last keyframe below which the safety cue should fire.
    private let safetyMargin: Double

    // Advances on the commit *decision*, not after the adapter's disk write succeeds — this
    // struct never touches disk, so it can't know whether the write lands. On the rare
    // write-failure path (adapter skips the keyframe; see SampleHandler.commitKeyframe) this
    // leaves a permanent gap in kf-NNNN numbering and in session.keyframes[].index, instead of
    // the old inline behaviour of reusing the number on the next attempt. That's inert:
    // downstream (Compositor) looks keyframes up by `index` value — a dictionary keyed by index,
    // plus a sort by index — and never assumes the indices are contiguous.
    private var keyframeIndex = 0
    // Most-recent processed frame, retained only so content scrolled past the last committed
    // keyframe can be banked as the trailing keyframe in finish().
    private var lastImage: CGImage?
    private var lastProfile: FrameProfile?

    public init(
        profiler: VerticalProfile = VerticalProfile(),
        selector: KeyframeSelector = KeyframeSelector(),
        safetyMargin: Double = 0.4
    ) {
        self.profiler = profiler
        self.selector = selector
        self.safetyMargin = safetyMargin
    }

    /// Profile one frame and decide whether to bank it. The adapter passes the same image it just
    /// received; when `Step.keyframe` is non-nil the adapter writes *that image's* bytes.
    public mutating func ingest(_ image: CGImage) -> Step {
        let profile = profiler.profile(image)
        let result = selector.evaluate(profile)
        let fireSafetyCue = result.overlapFraction < safetyMargin

        var captured: CapturedKeyframe?
        if result.commit {
            captured = CapturedKeyframe(image: image, metadata: makeMetadata(for: image))
            keyframeIndex += 1   // advances on the decision, not the write — see property comment
        }
        lastImage = image
        lastProfile = profile
        return Step(keyframe: captured, fireSafetyCue: fireSafetyCue)
    }

    /// The `broadcastFinished` trailing commit: bank the last frame only if there is real
    /// uncommitted downward motion since the last keyframe, so a near-duplicate tail (which the
    /// app would read as a non-overlapping gap) is not banked.
    public mutating func finish() -> CapturedKeyframe? {
        guard let image = lastImage, let profile = lastProfile,
              selector.hasUncommittedMotion(profile) else { return nil }
        let captured = CapturedKeyframe(image: image, metadata: makeMetadata(for: image))
        keyframeIndex += 1   // advances on the decision, not the write — see property comment
        return captured
    }

    private func makeMetadata(for image: CGImage) -> Keyframe {
        Keyframe(
            filename: String(format: "kf-%04d.bgra", keyframeIndex),
            pixelWidth: image.width,
            pixelHeight: image.height,
            index: keyframeIndex
        )
    }
}
