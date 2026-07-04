import Testing
import Foundation
@testable import StitchKit

@Suite struct StitchSessionTests {
    private func sampleSession() -> StitchSession {
        StitchSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            status: .recording,
            deviceScale: 3.0,
            orientation: .portrait,
            colorSpaceName: "kCGColorSpaceDisplayP3",
            keyframes: [
                Keyframe(filename: "kf-0000.heic", pixelWidth: 1290, pixelHeight: 2796, index: 0),
                Keyframe(filename: "kf-0001.heic", pixelWidth: 1290, pixelHeight: 2796, index: 1),
            ],
            seams: [Seam(fromIndex: 0, provisionalDy: 1800, confidence: 0.92, chromeTopPixels: 150, chromeBottomPixels: 120)],
            segmentBreaks: []
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = sampleSession()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StitchSession.self, from: data)
        #expect(decoded == original)
    }

    @Test func incrementalAppendGrowsManifest() {
        var session = sampleSession()
        #expect(session.keyframes.count == 2)
        session.keyframes.append(Keyframe(filename: "kf-0002.heic", pixelWidth: 1290, pixelHeight: 2796, index: 2))
        session.seams.append(Seam(fromIndex: 1, provisionalDy: 1750, confidence: 0.88))
        #expect(session.keyframes.count == 3)
        #expect(session.seams.count == 2)
    }

    @Test func statusTransitionsRecordingToComplete() {
        var session = sampleSession()
        #expect(session.status == .recording)
        session.status = .complete
        #expect(session.status == .complete)
    }

    @Test func needsTwoKeyframesToStitch() {
        var session = sampleSession()
        #expect(session.hasStitchableContent)
        session.keyframes.removeLast()
        #expect(!session.hasStitchableContent)
    }

    @Test func reportsSegmentBreakAfterIndex() {
        var session = sampleSession()
        #expect(!session.hasSegmentBreak(after: 0))
        session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock))
        #expect(session.hasSegmentBreak(after: 0))
        #expect(!session.hasSegmentBreak(after: 1))
    }

    @Test func decodesManifestMissingLaterFields() throws {
        // A manifest written before topTrim/bottomTrim existed must still decode (defaulting),
        // not throw and silently drop the capture.
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","createdAt":1000000,
         "status":"complete","deviceScale":3,"orientation":"portrait",
         "keyframes":[],"seams":[],"segmentBreaks":[]}
        """
        let decoder = JSONDecoder()
        let session = try decoder.decode(StitchSession.self, from: Data(json.utf8))
        #expect(session.topTrim == 0)
        #expect(session.bottomTrim == 0)
        #expect(session.status == .complete)
    }

    @Test func frameProfileExposesRowGeometry() {
        let profile = FrameProfile(means: [0.1, 0.2, 0.3, 0.4], variances: [0, 0, 0, 0], sourceWidth: 100, sourceHeight: 800)
        #expect(profile.rowCount == 4)
        #expect(profile.rowScale == 200)
    }
}
