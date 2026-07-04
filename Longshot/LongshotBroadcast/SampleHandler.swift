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
    private let chromeDetector = ChromeDetector()
    private var tracker = PositionTracker()
    private var selector = FrameSelector()

    private var store: SessionStore?
    private var folder: URL?
    private var session: StitchSession?

    private var keyframeIndex = 0
    private var lastKeyframeProfile: FrameProfile?
    private var lastKeyframeRow = 0
    private var lastSegment = 0
    private var framesSinceCue = 1_000

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.lilikazine.Longshot") else {
            finishBroadcastWithError(NSError(domain: "Longshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"]))
            return
        }
        let store = SessionStore(containerURL: container)
        let session = StitchSession(createdAt: Date(), status: .recording, deviceScale: 1, orientation: .portrait)
        self.store = store
        self.session = session
        self.folder = try? store.createFolder(for: session.id)
        try? store.writeManifest(session)
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
    }

    override func broadcastFinished() {
        guard var session, let store else { return }
        session.status = .complete
        self.session = session
        try? store.writeManifest(session)
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
        do { try KeyframeIO.writeRaw(image, to: url) } catch { return }

        session.keyframes.append(Keyframe(filename: filename, pixelWidth: image.width, pixelHeight: image.height, index: keyframeIndex))

        if case .segmentBreak(let reason) = result.decision, keyframeIndex > 0 {
            session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: keyframeIndex - 1, reason: reason))
        } else if keyframeIndex > 0, result.segmentIndex == lastSegment, let previous = lastKeyframeProfile {
            let dyRows = max(0, result.position - lastKeyframeRow)
            let dyPixels = Int(Double(dyRows) * profile.rowScale)
            let bands = chromeDetector.detect(previous, profile, dy: dyRows)
            session.seams.append(Seam(
                fromIndex: keyframeIndex - 1,
                provisionalDy: dyPixels,
                confidence: result.confidence,
                chromeTopPixels: Int(Double(bands.topRows) * profile.rowScale),
                chromeBottomPixels: Int(Double(bands.bottomRows) * profile.rowScale),
                isLowConfidence: bands.isAmbiguous || result.confidence < 0.4
            ))
        }

        lastKeyframeProfile = profile
        lastKeyframeRow = result.position
        lastSegment = result.segmentIndex
        keyframeIndex += 1
        self.session = session
        try? store.writeManifest(session)   // incremental
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
