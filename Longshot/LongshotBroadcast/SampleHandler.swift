import ReplayKit
import CoreImage
import CoreMedia
import CoreVideo
import AudioToolbox
import Darwin
import Foundation
import StitchKit

/// Receives live screen frames from ReplayKit and does only the minimum real-time work:
/// profile each frame and, via `KeyframeSelector`, bank a keyframe whenever the view has
/// scrolled far enough. It builds **no** geometry (order/seams/segments/bands) and does no
/// compositing — the app re-derives all of that from the captured keyframes with
/// `BatchStitcher`. Keeping the extension's job to "save overlapping keyframes + a keyframe list"
/// is what makes capture robust; the fragile streaming tracker used to lose lock and produce
/// nothing.
///
/// Memory discipline (the ~50 MB extension ceiling): hold at most one full frame at a time,
/// copy out what's needed and release the pixel buffer immediately, and keep everything else
/// 1-D. Keyframes are written raw BGRA-to-disk (allocation-free, no encoder spike).
class SampleHandler: RPBroadcastSampleHandler {
    // Fallback decoder only — created lazily, so the common 32BGRA path (PixelBufferImage) never
    // pays the GPU CIContext's memory baseline that was pushing the extension past its ceiling.
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let profiler = VerticalProfile()
    private var selector = KeyframeSelector()
    /// Overlap fraction with the last keyframe below which the safety cue fires.
    private let safetyMargin = 0.4

    private var store: SessionStore?
    private var folder: URL?
    private var session: StitchSession?

    private var keyframeIndex = 0
    private var framesSinceCue = 1_000

    // Most-recent processed frame, retained only so content scrolled past the last committed
    // keyframe can be committed as the trailing keyframe in broadcastFinished().
    private var lastImage: CGImage?
    private var lastProfile: FrameProfile?

    // MARK: - Diagnostic trace
    // The extension can't present UI and its App Group container isn't reliably pullable over USB,
    // so every notable event goes to `Diagnostics`: the unified log (Console.app in real time) and
    // a durable App Group file the app can read back and share. This is how a capture that produces
    // no output stays diagnosable after the fact.
    private var frameCount = 0
    private static let debugGroupID = "group.io.github.lilikazine.Longshot"
    private let diag = Diagnostics(
        containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SampleHandler.debugGroupID),
        category: .capture
    )
    private func dlog(_ message: String) { diag.log(message) }

    /// Current physical memory footprint in MB (the number ReplayKit's ~50 MB ceiling is measured
    /// against), or -1 if it can't be read. Used only for the diagnostic trace.
    private func memoryFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / (1024 * 1024)) : -1
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.lilikazine.Longshot")
        dlog("broadcastStarted: container=\(container?.path ?? "NIL")")
        guard let container else {
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
            dlog("broadcastStarted: session=\(session.id.uuidString) folder created")
        } catch {
            dlog("broadcastStarted: createFolder FAILED \(error)")
            finishBroadcastWithError(NSError(domain: "Longshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't create capture storage"]))
            return
        }
        do {
            try store.writeManifest(session)
        } catch {
            // Non-fatal: the incremental writes in commitKeyframe retry this. Log so a
            // shared-container write problem is diagnosable rather than silent.
            dlog("broadcastStarted: initial manifest write failed \(error)")
            NSLog("Longshot: initial manifest write failed: \(error)")
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        // A broadcast upload extension has a hard ~50 MB footprint ceiling and frames arrive far
        // faster than the run loop drains its autorelease pool, so the per-frame CIImage/CGImage/
        // pixel-buffer temporaries pile up and the extension is jetsam-killed (no crash log, no
        // broadcastFinished) — which is exactly the "stops after the first frame" symptom. Draining
        // per frame keeps the footprint flat.
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { dlog("frame: nil pixelBuffer"); return }

            // Copy out a CGImage and let the pixel buffer go — never retain it across frames. The
            // direct path (no Core Image / GPU) keeps the per-frame footprint far under the ~50 MB
            // ceiling; the CIContext is a lazy fallback only for an unexpected non-BGRA format.
            let image: CGImage
            if let direct = PixelBufferImage.makeCGImage(from: pixelBuffer) {
                image = direct
            } else {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                guard let fallback = ciContext.createCGImage(ciImage, from: ciImage.extent) else { dlog("frame: createCGImage nil"); return }
                dlog("frame: non-BGRA, used CIContext fallback")
                image = fallback
            }

            frameCount += 1
            // Trace the first frames in detail (that's where it was dying) and a heartbeat after,
            // each with the memory footprint so a climb toward the ceiling is visible.
            let trace = frameCount <= 5 || frameCount % 60 == 0
            if trace { dlog("frame \(frameCount): decoded \(image.width)x\(image.height) mem=\(memoryFootprintMB())MB") }

            let profile = profiler.profile(image)
            let result = selector.evaluate(profile)
            if trace { dlog("frame \(frameCount): commit=\(result.commit) overlap=\(String(format: "%.2f", result.overlapFraction)) kf=\(keyframeIndex) mem=\(memoryFootprintMB())MB") }

            if result.overlapFraction < safetyMargin { fireSafetyCue() } else { framesSinceCue += 1 }

            if result.commit { commitKeyframe(image, profile: profile) }

            lastImage = image
            lastProfile = profile
        }
    }

    override func broadcastFinished() {
        // Commit the trailing frame so content scrolled past the last keyframe isn't dropped —
        // but only if there's real uncommitted motion, so a near-duplicate tail isn't banked
        // (which the app would read as a non-overlapping gap).
        if let image = lastImage, let profile = lastProfile, selector.hasUncommittedMotion(profile) {
            commitKeyframe(image, profile: profile)
        }
        dlog("broadcastFinished: frames=\(frameCount) keyframes=\(keyframeIndex)")

        guard var session, let store else { dlog("broadcastFinished: no session/store"); return }
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

    /// Bank one keyframe: write the raw frame and append it to the manifest's keyframe list.
    /// No order/seams/segments/bands are recorded here — the app re-derives all geometry from
    /// the keyframes with `BatchStitcher`, so the extension only needs to preserve the frames.
    private func commitKeyframe(_ image: CGImage, profile: FrameProfile) {
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
            dlog("keyframe \(keyframeIndex) write FAILED (\(filename)): \(error.localizedDescription)")
            NSLog("Longshot: keyframe write failed (\(filename)): \(error)")
            return
        }

        dlog("keyframe \(keyframeIndex) written (\(image.width)x\(image.height))")
        session.keyframes.append(Keyframe(filename: filename, pixelWidth: image.width, pixelHeight: image.height, index: keyframeIndex))
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
