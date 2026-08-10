import Testing
import Foundation
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
