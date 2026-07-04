import ReplayKit
import CoreImage
import CoreMedia
import CoreVideo
import AudioToolbox
import Foundation
import StitchKit

/// Receives live screen frames from ReplayKit and runs only the lightweight StitchKit steps —
/// profiling, position tracking, keyframe selection, chrome detection, and the safety cue —
/// streaming selected keyframes plus an incremental manifest to the App Group. It does **no**
/// compositing; the app assembles everything afterward.
///
/// Memory discipline (the ~50 MB extension ceiling): hold at most one full frame at a time,
/// copy out what's needed and release the pixel buffer immediately, and keep everything else
/// 1-D. Keyframes are written raw BGRA-to-disk (allocation-free, no encoder spike).
class SampleHandler: RPBroadcastSampleHandler {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let profiler = VerticalProfile()
    private var tracker = PositionTracker()
    private var selector = FrameSelector()

    private var store: SessionStore?
    private var folder: URL?
    private var session: StitchSession?

    private var keyframeIndex = 0
    private var lastKeyframeRow = 0
    private var lastSegment = 0
    private var framesSinceCue = 1_000

    // Most-recent processed frame, retained only so the trailing content below the last
    // keyframe (and the final bottom chrome) can be committed in broadcastFinished().
    private var lastImage: CGImage?
    private var lastProfile: FrameProfile?
    private var lastResult: TrackingResult?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.lilikazine.Longshot") else {
            finishBroadcastWithError(NSError(domain: "Longshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"]))
            return
        }
        let store = SessionStore(containerURL: container)
        let session = StitchSession(createdAt: Date(), status: .recording, deviceScale: 1, orientation: .portrait)
        self.store = store
        self.session = session
        do {
            // Without a session folder there is nowhere to write keyframes — the whole
            // broadcast would silently produce nothing. Fail loudly instead.
            self.folder = try store.createFolder(for: session.id)
        } catch {
            finishBroadcastWithError(NSError(domain: "Longshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't create capture storage"]))
            return
        }
        do {
            try store.writeManifest(session)
        } catch {
            // Non-fatal: the incremental writes in commitKeyframe retry this. Log so a
            // shared-container write problem is diagnosable rather than silent.
            NSLog("Longshot: initial manifest write failed: \(error)")
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Copy out a CGImage and let the pixel buffer go — never retain it across frames.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let profile = profiler.profile(image)
        let result = tracker.process(profile)

        if result.needsSafetyCue { fireSafetyCue() } else { framesSinceCue += 1 }

        if selector.evaluate(result, bandHeight: profile.rowCount) == .commitKeyframe {
            commitKeyframe(image, profile: profile, result: result)
        }

        lastImage = image
        lastProfile = profile
        lastResult = result
    }

    override func broadcastFinished() {
        // Commit the trailing frame so content scrolled past the last keyframe (and the final
        // bottom chrome) isn't dropped.
        if selector.finish() == .commitKeyframe, let image = lastImage, let profile = lastProfile, let result = lastResult {
            commitKeyframe(image, profile: profile, result: result)
        }

        guard var session, let store else { return }
        session.status = .complete
        self.session = session
        do {
            try store.writeManifest(session)
        } catch {
            // The app can still recover this capture via the staleness heuristic, but log:
            // a failed final write is why a finished capture might import as "incomplete".
            NSLog("Longshot: final manifest write failed: \(error)")
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("io.github.lilikazine.Longshot.sessionFinished" as CFString),
            nil, nil, true
        )
    }

    // MARK: - Keyframe commit

    private func commitKeyframe(_ image: CGImage, profile: FrameProfile, result: TrackingResult) {
        guard var session, let folder, let store else { return }

        if keyframeIndex == 0 {
            session.orientation = image.width > image.height ? .landscape : .portrait
            session.colorSpaceName = image.colorSpace?.name as String?
        }

        let filename = String(format: "kf-%04d.bgra", keyframeIndex)
        let url = folder.appendingPathComponent(filename)
        do {
            try KeyframeIO.writeRaw(image, to: url)
        } catch {
            // Skip this keyframe but keep the broadcast running. Log so a run that drops
            // frames (e.g. the container filling up) isn't a silent gap in the stitch.
            NSLog("Longshot: keyframe write failed (\(filename)): \(error)")
            return
        }

        session.keyframes.append(Keyframe(filename: filename, pixelWidth: image.width, pixelHeight: image.height, index: keyframeIndex))

        if case .segmentBreak(let reason) = result.decision, keyframeIndex > 0 {
            session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: keyframeIndex - 1, reason: reason))
        } else if keyframeIndex > 0, result.segmentIndex == lastSegment {
            let dyRows = max(0, result.position - lastKeyframeRow)
            let dyPixels = Int(Double(dyRows) * profile.rowScale)
            session.seams.append(Seam(
                fromIndex: keyframeIndex - 1,
                provisionalDy: dyPixels,
                confidence: result.confidence,
                isLowConfidence: result.confidence < 0.4
            ))
        }

        // Record/refresh this segment's content band. It locks mid-segment via consensus, so
        // the last write per segment carries the settled band (or `.unlocked` if none locked).
        let seg = result.segmentIndex
        while session.contentBands.count <= seg { session.contentBands.append(.unlocked) }
        session.contentBands[seg] = result.contentBand

        lastKeyframeRow = result.position
        lastSegment = result.segmentIndex
        keyframeIndex += 1
        self.session = session
        // Best-effort incremental checkpoint: the next keyframe writes the manifest again and
        // broadcastFinished() writes the authoritative final copy, so a dropped write here is
        // recovered by the following one. Intentionally not surfaced per-frame.
        try? store.writeManifest(session)
    }

    // MARK: - Safety cue

    /// Fire a sound + haptic when overlap drops toward the loss threshold. Whether either
    /// channel is audible from a broadcast extension is a device go/no-go (see the design's
    /// early verifications); if neither works we fall back to onboarding + detect-and-segment.
    private func fireSafetyCue() {
        guard framesSinceCue > 45 else { return }   // throttle: at most ~once per 45 frames
        framesSinceCue = 0
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
    }
}
