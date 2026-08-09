import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// "From Photos" with the screenshots picked out of order — the reported failure: a set that
/// stitches perfectly when tapped top-to-bottom shatters when tapped in a random order.
///
/// Order recovery was not at fault. `BatchStitcher.plan` recovers this set exactly from any
/// permutation (`ScreenshotOrderRecoveryTests` pins that on the same pixels). The loss happened
/// one layer up: `resolveGeometry`'s `.recoverOrInputOrder` gate treated a low-confidence *seam*
/// as evidence that the recovered *order* was untrustworthy. At the time, this set's seam 2→3
/// measured 0.368 — under the 0.4 floor — so the correct recovered order was discarded in favour
/// of pick order on every import. It now measures about 0.726; the policy test injects a 0.8 flag
/// threshold to reproduce the historical condition without relying on stale matcher output.
///
/// Seam confidence is a statement about one seam's *offset*, not whether ordering succeeded. Only
/// a segment break engages fallback: separate components have no measured relation to each other,
/// so their relative order comes from input index, i.e. a guess, and there the caller's guess is
/// the better one. The assumed-order pass still measures neighbours and keeps genuine breaks.
///
/// Real pixels, not synthetic: no synthetic ramp lands a seam in (0, 0.4) while still chaining
/// correctly, and a set that *doesn't* reproduce the trap cannot pin this fix. The fixtures are
/// shared with `StitchKitTests` by source-relative path rather than duplicating 9 MB of PNGs into
/// the app test bundle; they are still deterministic, checked-in files, never a library lookup.
@MainActor
struct PhotoPickOrderTests {

    /// Three consecutive screenshots of the same scroll, in true scroll order. This subset is the
    /// minimal reproduction: it chains into one segment and contains the seam that historically
    /// scored 0.368 (about 0.726 now, flagged by the injected 0.8 threshold).
    static let scrollOrder = ["IMG_1758.PNG", "IMG_1759.PNG", "IMG_1760.PNG"]

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()        // SeamlyTests/
        .deletingLastPathComponent()        // Seamly/
        .appendingPathComponent("StitchKit/Tests/StitchKitTests/Fixtures/Screenshots")

    /// Copy `names` into a fresh session folder as PNG keyframes, indexed in the order given (the
    /// pick order), and return the manifest. PNGs rather than `.bgra`: `loadKeyframe` picks the
    /// reader by extension, and these are 15 MB each raw.
    private func writePickedSession(_ names: [String], root: URL) throws -> (StitchSession, URL) {
        let store = SessionStore(containerURL: root)
        let id = UUID()
        let folder = try store.createFolder(for: id)
        var session = StitchSession(id: id, createdAt: Date(), status: .complete, deviceScale: 1,
                                    orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String)
        for (i, name) in names.enumerated() {
            let source = Self.fixtures.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
            let image = try KeyframeIO.read(from: source)
            session.keyframes.append(Keyframe(filename: name, pixelWidth: image.width,
                                              pixelHeight: image.height, index: i))
        }
        try store.writeManifest(session)
        return (session, folder)
    }

    /// The regression. Screenshots handed over in a scrambled pick order must come back in scroll
    /// order — recovery already knows it, and one fuzzy seam is no reason to unlearn it.
    @Test func shuffledPickOrderIsReorderedIntoScrollOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let picked = [Self.scrollOrder[2], Self.scrollOrder[0], Self.scrollOrder[1]]
        let (session, folder) = try writePickedSession(picked, root: root)

        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: .recoverOrInputOrder)

        #expect(resolved.keyframes.map(\.filename) == Self.scrollOrder,
                "kept the pick order instead of the recovered scroll order")
        #expect(resolved.keyframes.map(\.index) == [0, 1, 2])
        #expect(resolved.segmentBreaks.isEmpty)
    }

    /// The badge means "the order is a guess". A complete recovered chain is not a guess, however
    /// fuzzy one of its seams is, so it must not be badged — otherwise the badge degrades into
    /// "recovery wasn't perfect" and stops telling the user anything actionable. The fuzzy seam is
    /// still reported, on the seam itself, where the editor already surfaces it.
    ///
    /// The flag threshold is raised so the fuzzy seam is guaranteed rather than hoped for. This
    /// set used to score 0.368 on seam 2→3 and now scores 0.726 — same offsets, better-calibrated
    /// confidence after the masked overlap floor was corrected — so at the shipping 0.4 there is
    /// no longer a fuzzy seam here to not-badge, and the assertion below would pass without ever
    /// exercising the bug it was written for.
    @Test func aFuzzySeamDoesNotBadgeTheOrderAsAssumed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session, folder) = try writePickedSession(Self.scrollOrder, root: root)

        let resolved = try StitchAssembler.resolveGeometry(
            session, in: folder,
            strategy: .recoverOrInputOrder,
            stitcher: BatchStitcher(lowConfidenceSeam: 0.8)
        )

        let fuzzy = resolved.seams.filter(\.isLowConfidence)
        #expect(!fuzzy.isEmpty, "flag threshold no longer reproduces the trap: \(resolved.seams.map(\.confidence))")
        #expect(resolved.orderAssumed == false, "a fully chained recovery was badged 'order assumed'")
    }
}
