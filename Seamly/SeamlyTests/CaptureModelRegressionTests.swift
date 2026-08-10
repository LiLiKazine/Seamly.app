import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Regression coverage for three defects found in review of the `HomeView` shell (Task 7):
/// the "stitching…" busy signal getting stuck, an empty-pickup nudge silently dropped on a
/// second occurrence, and two triggers racing `refresh()` concurrently.
@MainActor
struct CaptureModelRegressionTests {

    /// `isAssemblingNewArrival` must reflect *actual* in-flight work, not a scan of every
    /// capture's `phase`. `reload()` (invoked by every import, via `runImport`) demotes *every*
    /// not-yet-ready capture back to `.processing` — including one that already failed and
    /// will not be touched again until the next `refresh()`. A naive "any capture is
    /// `.processing`" signal reads busy forever from that point on, permanently covering home
    /// behind an overlay with no escape but backgrounding the app.
    @Test func arrivalAssemblyClearsEvenWithAStrayFailedCapture() async throws {
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

        // Now perform a real, unrelated import — a genuine new arrival — while the failed
        // capture sits at `.failed`.
        await model.importPhotos(MediaImportTests.slices(count: 3, width: 120, sliceH: 360, dy: 140))

        // Confirm the premise this test guards against actually holds, so the assertion below
        // is meaningful and not vacuous: `reload()` really did stomp the failed capture back to
        // `.processing`, and it was never reassembled (nobody called `assemble` for it).
        let strayCapture = try #require(model.captures.first { $0.id == failingID })
        #expect(strayCapture.phase == .processing)
        #expect(strayCapture.proxy == nil)
        let anyCaptureProcessing = model.captures.contains { $0.phase == .processing }
        #expect(anyCaptureProcessing)   // the naive "any .processing" signal reads busy here

        // The genuinely new import already finished assembling by the time `importPhotos`
        // returns — nothing should still report busy on its account, and the stray
        // `.processing` capture above — never actually being worked on — must not count either.
        #expect(model.isAssemblingNewArrival == false)
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
