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
    /// The pure picking loop (profile → KeyframeSelector → keyframe metadata + safety-cue
    /// decision + trailing commit). This adapter only decodes frames, writes bytes, updates the
    /// manifest, and plays haptics; all capture *decisions* live in the driver.
    private var driver = ScrollCaptureDriver(safetyMargin: 0.4)

    private var store: SessionStore?
    private var folder: URL?
    private var session: StitchSession?

    private var keyframeIndex = 0
    private var framesSinceCue = 1_000

    // MARK: - Diagnostic trace
    // The extension can't present UI and its App Group container isn't reliably pullable over USB,
    // so every notable event goes to `Diagnostics`: the unified log (Console.app in real time) and
    // a durable App Group file the app can read back and share. This is how a capture that produces
    // no output stays diagnosable after the fact.
    private var frameCount = 0
    private let diag = Diagnostics(containerURL: AppGroup.containerURL, category: .capture)
    private func dlog(_ message: String) { diag.log(message) }

    /// Consecutive failed per-keyframe manifest checkpoints. A single failure is recovered by the
    /// next keyframe's write, so it isn't worth a line; a *run* of them means the container is
    /// unwritable and the capture will import short or not at all, which must be diagnosable.
    private var checkpointFailures = 0

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
        let container = AppGroup.containerURL
        dlog("broadcastStarted: container=\(container?.path ?? "NIL")")
        guard let container else {
            finishBroadcastWithError(NSError(domain: "Seamly", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"]))
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
            finishBroadcastWithError(NSError(domain: "Seamly", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't create capture storage"]))
            return
        }
        do {
            try store.writeManifest(session)
        } catch {
            // Non-fatal: the incremental writes in commitKeyframe retry this. Log so a
            // shared-container write problem is diagnosable rather than silent.
            dlog("broadcastStarted: initial manifest write failed \(error)")
            NSLog("Seamly: initial manifest write failed: \(error)")
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

            let step = driver.ingest(image)
            if trace { dlog("frame \(frameCount): commit=\(step.keyframe != nil) cue=\(step.fireSafetyCue) kf=\(keyframeIndex) mem=\(memoryFootprintMB())MB") }

            if step.fireSafetyCue { fireSafetyCue() } else { framesSinceCue += 1 }
            if let captured = step.keyframe { commitKeyframe(captured) }
        }
    }

    override func broadcastFinished() {
        // Commit the trailing frame so content scrolled past the last keyframe isn't dropped —
        // the driver returns it only when there's real uncommitted motion (never a near-duplicate).
        if let captured = driver.finish() { commitKeyframe(captured) }
        dlog("broadcastFinished: frames=\(frameCount) keyframes=\(keyframeIndex)")

        guard var session, let store else { dlog("broadcastFinished: no session/store"); return }
        session.status = .complete
        self.session = session
        do {
            try store.writeManifest(session)
        } catch {
            // The app can still recover this capture via the staleness heuristic, but log:
            // a failed final write is why a finished capture might import as "incomplete".
            // Via `dlog` too, not just NSLog — the durable App Group file is the only channel
            // the user can hand back after the fact, and this is exactly that kind of failure.
            dlog("broadcastFinished: final manifest write FAILED: \(error.localizedDescription)")
            NSLog("Seamly: final manifest write failed: \(error)")
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroup.sessionFinishedNotification as CFString),
            nil, nil, true
        )
    }

    // MARK: - Keyframe commit

    /// Bank one driver-selected keyframe: write its raw bytes and append its manifest entry. No
    /// order/seams/segments/bands here — the app re-derives all geometry with `BatchStitcher`.
    private func commitKeyframe(_ captured: ScrollCaptureDriver.CapturedKeyframe) {
        guard var session, let folder, let store else { return }
        let image = captured.image
        let meta = captured.metadata

        if meta.index == 0 {
            session.orientation = image.width > image.height ? .landscape : .portrait
            session.colorSpaceName = image.colorSpace?.name as String?
        }

        let url = folder.appendingPathComponent(meta.filename)
        do {
            try KeyframeIO.writeRaw(image, to: url)
        } catch {
            // Skip this keyframe but keep the broadcast running. Log so a run that drops
            // frames (e.g. the container filling up) isn't a silent gap in the stitch.
            dlog("keyframe \(meta.index) write FAILED (\(meta.filename)): \(error.localizedDescription)")
            NSLog("Seamly: keyframe write failed (\(meta.filename)): \(error)")
            return
        }

        dlog("keyframe \(meta.index) written (\(image.width)x\(image.height))")
        session.keyframes.append(meta)
        // Mirrors the driver's monotonic index (not "count of keyframes written"): a write
        // failure above returns before this line, so a dropped keyframe leaves a gap here too
        // rather than reusing the number — safe, since downstream looks keyframes up by index.
        // Consequence for first-keyframe metadata: the orientation/colorSpace capture above is
        // gated on `meta.index == 0`, so if the very first keyframe's write fails (index 0 never
        // successfully commits), session orientation/colorSpace stay at their defaults
        // (`.portrait` / `nil`) — a benign edge, since it only bites on a first-frame write
        // failure and those fallbacks are safe.
        keyframeIndex = meta.index + 1
        self.session = session
        // Incremental checkpoint. One failure is genuinely recoverable — the next keyframe rewrites
        // the manifest and broadcastFinished() writes the authoritative final copy — so it isn't
        // surfaced to the user and isn't logged per-frame (this runs once per keyframe and a flood
        // would push the real trace out of the size-capped log). But the manifest is what makes a
        // capture importable at all, so a *persistent* failure (disk full, container gone) must not
        // vanish: log the first, then every 10th, so the trace shows both onset and duration.
        do {
            try store.writeManifest(session)
            if checkpointFailures > 0 {
                dlog("manifest checkpoint recovered after \(checkpointFailures) consecutive failure(s)")
                checkpointFailures = 0
            }
        } catch {
            checkpointFailures += 1
            if checkpointFailures == 1 || checkpointFailures % 10 == 0 {
                dlog("manifest checkpoint FAILED (\(checkpointFailures) consecutive, at keyframe \(meta.index)): \(error.localizedDescription)")
            }
        }
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
