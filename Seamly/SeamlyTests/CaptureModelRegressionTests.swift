import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Regression coverage for defects found across two rounds of review of the `HomeView` shell
/// (Task 7): the "stitching…" busy signal getting stuck (or never appearing at all), an
/// empty-pickup nudge silently dropped on a second occurrence (including the case where a
/// second `refresh()` pass sees an already-emptied group), and two triggers racing `refresh()`
/// concurrently.
@MainActor
struct CaptureModelRegressionTests {

    /// `isAssemblingNewArrival` must reflect *actual* in-flight work, not a scan of every
    /// capture's `phase`. `reload()` (invoked by every import, via `runImport`) demotes *every*
    /// not-yet-ready capture back to `.processing` — including one that already failed and
    /// will not be touched again until the next `refresh()`. A naive "any capture is
    /// `.processing`" signal reads busy forever from that point on, permanently covering home
    /// behind an overlay with no escape but backgrounding the app.
    ///
    /// This must constrain *both* directions: deleting the `arrivalAssemblyCount` increment/
    /// decrement pair entirely would leave the signal permanently `false` (an overlay that
    /// never appears at all) and still pass an assertion that only checks it eventually clears
    /// — so this also asserts it reports busy *while genuinely assembling*, not just that it
    /// settles back to `false` afterwards.
    @Test func arrivalAssemblyReportsBusyOnlyForGenuineWorkNotAStrayFailedCapture() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("app")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: app, withIntermediateDirectories: true)

        let model = CaptureModel(appContainer: app, groupContainer: nil)

        // Seed a capture that will fail to assemble: a manifest whose keyframe files don't
        // exist on disk (mirrors `BroadcastImportTests`' "no real pixel bytes" setup), so
        // `StitchAssembler.composite` throws and the capture lands at `.failed`.
        let store = SessionStore(containerURL: app)
        let failingID = UUID()
        _ = try store.createFolder(for: failingID)
        var failing = StitchSession(
            id: failingID, createdAt: Date(), status: .complete, deviceScale: 1,
            orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String
        )
        failing.keyframes = [
            Keyframe(filename: "missing-0.bgra", pixelWidth: 10, pixelHeight: 10, index: 0),
            Keyframe(filename: "missing-1.bgra", pixelWidth: 10, pixelHeight: 10, index: 1)
        ]
        try store.writeManifest(failing)

        await model.refresh()   // assembles the seeded session; it fails (files don't exist)
        let phaseAfterSeed = try #require(model.captures.first { $0.id == failingID }).phase
        guard case .failed = phaseAfterSeed else {
            Issue.record("expected the seeded capture to fail assembly, got \(phaseAfterSeed)")
            return
        }

        // Seed a second, real capture straight onto disk — deliberately large, so its eventual
        // composite takes long enough to reliably observe with a coarse poll rather than racing
        // a near-instant one — but not yet assembled. Writing it directly (not via
        // `MediaImporter`) keeps this test from also depending on `MediaImporter`'s own
        // order-recovery search, a separate, larger cost unrelated to what's under test here
        // (see the report's note on the `runImport` gap).
        let arrivingID = UUID()
        let arrivingFolder = try store.createFolder(for: arrivingID)
        var arriving = StitchSession(
            id: arrivingID, createdAt: Date(), status: .complete, deviceScale: 1,
            orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String
        )
        let bigImages = MediaImportTests.slices(count: 6, width: 600, sliceH: 2000, dy: 1400)
        for (i, image) in bigImages.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: arrivingFolder.appendingPathComponent(name))
            arriving.keyframes.append(Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i))
        }
        try store.writeManifest(arriving)

        // A real, unrelated photo import — a genuine new arrival. `reload()` (inside
        // `importPhotos`) picks up *both* stray sessions now sitting on disk — the failed one
        // and the large one just seeded above — marking each `.processing` without assembling
        // either; only this call's own new id gets `assemble(..., announce: true)`.
        await model.importPhotos(MediaImportTests.slices(count: 3, width: 120, sliceH: 360, dy: 140))

        // Confirm the premise this test guards against actually holds, so the assertions below
        // are meaningful and not vacuous: `reload()` really did stomp the failed capture back to
        // `.processing`, the large one sits unassembled the same way, and neither was touched.
        let strayCapture = try #require(model.captures.first { $0.id == failingID })
        #expect(strayCapture.phase == .processing)
        #expect(strayCapture.proxy == nil)
        let arrivingBeforeAssembly = try #require(model.captures.first { $0.id == arrivingID })
        #expect(arrivingBeforeAssembly.phase == .processing)
        #expect(arrivingBeforeAssembly.proxy == nil)
        let anyCaptureProcessing = model.captures.contains { $0.phase == .processing }
        #expect(anyCaptureProcessing)   // the naive "any .processing" signal reads busy here

        // Nothing is genuinely in flight yet — the small import above already finished, and
        // the large capture above has only been *seeded*, not assembled.
        #expect(model.isAssemblingNewArrival == false)

        // Now exercise the true direction: actually assemble the large capture as a new
        // arrival, and confirm the flag reports busy *while it's really working* — not just
        // that it eventually clears (deleting the increment/decrement pair entirely would leave
        // it permanently `false` and still pass a clears-eventually-only assertion).
        async let arrivalAssembly: Void = model.assemble(arrivingID, announce: true)
        var observedBusy = false
        for _ in 0..<2000 {   // ~10s budget, generous margin over one composite's real duration
            if model.isAssemblingNewArrival { observedBusy = true; break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(observedBusy)

        await arrivalAssembly
        #expect(model.isAssemblingNewArrival == false)   // and clear again once it's done
    }

    /// `lastPickupWasEmpty` is an event ("a pickup was just empty"), not a level. Two
    /// consecutive empty pickups must each be independently observable — a second `true`
    /// written over an unconsumed `true` is not a change, so a view driven by `.onChange`
    /// would silently drop the second nudge entirely. `consumeLastPickupWasEmpty()` (mirroring
    /// `consumePendingResult()`) re-arms it.
    @Test func emptyPickupReannouncesAfterConsumption() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("app")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: app, withIntermediateDirectories: true)

        let model = CaptureModel(appContainer: app, groupContainer: nil)
        // A single photo: `MediaImporter` rejects fewer than two as `.notEnoughContent`.
        let single = MediaImportTests.slices(count: 1, width: 120, sliceH: 360, dy: 140)

        await model.importPhotos(single)
        #expect(model.lastPickupWasEmpty == true)

        model.consumeLastPickupWasEmpty()
        #expect(model.lastPickupWasEmpty == false)

        await model.importPhotos(single)   // a second, independent empty pickup
        #expect(model.lastPickupWasEmpty == true)   // must be observable again, not swallowed
    }

    /// `performRefresh` must only ever *raise* `lastPickupWasEmpty`, never clear it —
    /// `consumeLastPickupWasEmpty()` is the only place that may clear it. The coalescing loop
    /// added for the concurrent-`refresh()` fix guarantees a second pass runs immediately behind
    /// the first on the exact Control Center path: one pass discards an empty session and sets
    /// the flag `true`; the very next pass scans the now-emptied group and computes `sawEmpty
    /// == false`. An unconditional assignment in `performRefresh` would let that second, empty
    /// pass silently overwrite the first pass's still-unconsumed `true` before the shell ever
    /// observed it — this reproduces that exact two-pass sequence directly (no timing needed).
    @Test func emptyPickupSurvivesASecondRefreshPassThatSeesNothing() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupContainer = root.appendingPathComponent("group", isDirectory: true)
        let appContainer = root.appendingPathComponent("app", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: appContainer, withIntermediateDirectories: true)

        // A finalized session with a single keyframe: `hasStitchableContent` is false, so the
        // first `refresh()` discards it and reports an empty pickup.
        let sessionID = UUID()
        let groupStore = SessionStore(containerURL: groupContainer)
        var session = StitchSession(
            id: sessionID, createdAt: Date(), status: .complete, deviceScale: 1,
            orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String
        )
        session.keyframes = [Keyframe(filename: "kf-0000.bgra", pixelWidth: 10, pixelHeight: 10, index: 0)]
        try groupStore.writeManifest(session)

        let model = CaptureModel(appContainer: appContainer, groupContainer: groupContainer)

        await model.refresh()   // pass 1: discards the single-keyframe session, sees it empty
        #expect(model.lastPickupWasEmpty == true)

        await model.refresh()   // pass 2: nothing left in the group — this pass's own sawEmpty is false
        #expect(model.lastPickupWasEmpty == true)   // must survive; only consume may clear it
    }

    /// Both the `scenePhase` transition and the Darwin "broadcast finished" notification call
    /// `refresh()`, deliberately — a Control Center stop doesn't fire `scenePhase`. A Control
    /// Center stop can fire both within milliseconds of each other, so two unserialized scans
    /// race `importFromGroup()`'s `moveItem` for the same session: the loser throws (its
    /// `moveItem` source is already gone) and that failure is only logged, not surfaced, so the
    /// capture still ends up imported exactly once regardless — but the spurious failure log
    /// for a session that in fact imported fine is real, avoidable damage. An in-flight guard
    /// means the second call never touches the group scan while the first still owns it.
    @Test func concurrentRefreshesDoNotRaceTheGroupImport() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupContainer = root.appendingPathComponent("group", isDirectory: true)
        let appContainer = root.appendingPathComponent("app", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: appContainer, withIntermediateDirectories: true)

        let sessionID = UUID()
        let groupStore = SessionStore(containerURL: groupContainer)
        let folder = try groupStore.createFolder(for: sessionID)
        var session = StitchSession(
            id: sessionID, createdAt: Date(), status: .complete, deviceScale: 1,
            orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String
        )
        let images = MediaImportTests.slices(count: 3, width: 120, sliceH: 360, dy: 140)
        for (i, image) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
            session.keyframes.append(Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i))
        }
        try groupStore.writeManifest(session)

        let model = CaptureModel(appContainer: appContainer, groupContainer: groupContainer)

        // The exact Control Center race: two triggers call `refresh()` within milliseconds of
        // each other. `async let` fires them concurrently rather than sequentially.
        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        _ = await (first, second)

        #expect(model.captures.count == 1)
        let capture = try #require(model.captures.first { $0.id == sessionID })
        #expect(capture.phase == .ready)

        let shortID = sessionID.uuidString.prefix(8)
        let log = Diagnostics.readAll(containerURL: groupContainer)
        #expect(!log.contains("\(shortID) FAILED to import"))
    }
}
