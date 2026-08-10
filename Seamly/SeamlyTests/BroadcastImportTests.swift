import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Regression coverage for the app-side half of the broadcast hand-off: a finished session the
/// extension left in the App Group must be imported into app storage on `refresh()`, even on a
/// fresh install where the app's `sessions/` directory does not exist yet.
@MainActor
struct BroadcastImportTests {
    /// A finished, stitchable session in the group container shows up as a capture after refresh —
    /// this is the "coming back from a broadcast" main flow.
    @Test func finishedBroadcastSessionAppearsAfterRefresh() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupContainer = root.appendingPathComponent("group", isDirectory: true)
        let appContainer = root.appendingPathComponent("app", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        // Fresh install: the app's base container exists, but nothing has created `sessions/` yet.
        try fm.createDirectory(at: appContainer, withIntermediateDirectories: true)

        // Extension side: a finished session with two keyframes (stitchable) sitting in the group.
        let sessionID = UUID()
        let sessionDir = groupContainer
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try manifestJSON(id: sessionID).write(to: sessionDir.appendingPathComponent("manifest.json"))

        let model = CaptureModel(appContainer: appContainer, groupContainer: groupContainer)
        await model.refresh()

        #expect(model.captures.contains { $0.id == sessionID })
    }

    /// The hero path this whole feature exists for: record a broadcast, background the app,
    /// come back. A session with *real* stitchable pixel bytes (not just a manifest) sitting in
    /// the group container is a genuine new arrival — `refresh()` must set `pendingResult` to
    /// its id once assembly succeeds, so the shell can navigate straight to it. A second
    /// `refresh()`, with nothing new left in the group, must leave `pendingResult` nil once
    /// consumed — the session is now already in app storage, not a fresh arrival.
    @Test func newlyArrivedBroadcastSessionAnnouncesButASecondRefreshStaysSilent() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupContainer = root.appendingPathComponent("group", isDirectory: true)
        let appContainer = root.appendingPathComponent("app", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: appContainer, withIntermediateDirectories: true)

        // Extension side: a finished session with real, overlapping raw keyframes — genuinely
        // stitchable, so `assemble` succeeds rather than failing on a missing/corrupt file.
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
        await model.refresh()

        let capture = try #require(model.captures.first { $0.id == sessionID })
        #expect(capture.phase == .ready)   // real pixels: assembly actually succeeded
        #expect(model.pendingResult == sessionID)
        model.consumePendingResult()

        // Nothing left in the group this time — the session moved into app storage on the
        // first refresh — so this pass must not re-announce it.
        await model.refresh()
        #expect(model.pendingResult == nil)
    }

    private func manifestJSON(id: UUID) -> Data {
        """
        {
          "id": "\(id.uuidString)",
          "createdAt": "2026-07-04T12:00:00Z",
          "status": "complete",
          "deviceScale": 2,
          "orientation": "portrait",
          "keyframes": [
            { "id": "\(UUID().uuidString)", "filename": "kf-0000.bgra", "pixelWidth": 10, "pixelHeight": 10, "index": 0 },
            { "id": "\(UUID().uuidString)", "filename": "kf-0001.bgra", "pixelWidth": 10, "pixelHeight": 10, "index": 1 }
          ],
          "seams": [],
          "segmentBreaks": []
        }
        """.data(using: .utf8)!
    }
}
