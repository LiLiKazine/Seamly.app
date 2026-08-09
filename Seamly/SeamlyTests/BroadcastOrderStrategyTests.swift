import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Issue #8: broadcast import used `.recover` — "never fall back" — while being the path with the
/// most trustworthy input order. `ScrollCaptureDriver` numbers keyframes monotonically as it banks
/// them, so a broadcast session's stored order *is* capture order, exactly the temporal ordering
/// that justifies `.inputOrder` for video. It was also the only path with no safety net when
/// recovery mis-scores (issue #2).
///
/// The risk in switching is over-merging: a capture where the user switched apps mid-recording
/// genuinely is discontinuous and must keep its breaks. These tests pin both halves.
@MainActor
struct BroadcastOrderStrategyTests {

    private let helpers = MediaImportTests()

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// A clean broadcast-shaped session — overlapping frames in capture order — recovers normally
    /// and is *not* badged. The fallback must stay out of the way when recovery works.
    @Test func cleanBroadcastRecoversWithoutBadging() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let images = MediaImportTests.slices(count: 4, width: 120, sliceH: 360, dy: 140)
        let (store, id, folder) = try helpers.writeBase(images, root: root)

        let resolved = try StitchAssembler.resolveGeometry(store.readManifest(for: id), in: folder,
                                                           strategy: .recoverOrInputOrder)
        #expect(resolved.orderAssumed == false)
        #expect(resolved.segmentBreaks.isEmpty)
        #expect(resolved.keyframes.map(\.index) == [0, 1, 2, 3])
    }

    /// The over-merge guard, and the reason `.recoverOrInputOrder` is safe here: the fallback only
    /// stops *re-ordering*, it does not join anything. The assumed-order path still re-tests each
    /// consecutive pair for overlap (`BatchStitcher.segmentsAlong`) and breaks where there is none.
    ///
    /// Two frames from opposite ends of a tall source share no content, so they must land in
    /// separate segments even though the fallback has engaged.
    @Test func genuinelyNonOverlappingBroadcastStillSegments() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = MediaImportTests.makeSource(width: 120, height: 1200)
        let top = source.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300))!
        let bottom = source.cropping(to: CGRect(x: 0, y: 900, width: 120, height: 300))!
        let (store, id, folder) = try helpers.writeBase([top, bottom], root: root)

        let resolved = try StitchAssembler.resolveGeometry(store.readManifest(for: id), in: folder,
                                                           strategy: .recoverOrInputOrder)
        #expect(!resolved.segmentBreaks.isEmpty,
                "non-overlapping broadcast frames were force-merged into one segment")
        #expect(resolved.seams.isEmpty)
    }

    /// When recovery leaves a segment break, the fallback preserves capture order and says so.
    /// Seam confidence alone does not engage it. `orderAssumed` is what surfaces that choice to the
    /// user; broadcast previously took the mis-recovered result silently.
    @Test func unrecoverableBroadcastFallsBackAndBadges() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = MediaImportTests.makeSource(width: 120, height: 1200)
        let top = source.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300))!
        let bottom = source.cropping(to: CGRect(x: 0, y: 900, width: 120, height: 300))!
        let (store, id, folder) = try helpers.writeBase([top, bottom], root: root)

        let resolved = try StitchAssembler.resolveGeometry(store.readManifest(for: id), in: folder,
                                                           strategy: .recoverOrInputOrder)
        #expect(resolved.orderAssumed, "fallback engaged but the capture was not badged")
        // Capture order is preserved rather than re-sorted by a recovery that didn't chain.
        #expect(resolved.keyframes.map(\.filename) == ["kf-0000.bgra", "kf-0001.bgra"])
    }
}
