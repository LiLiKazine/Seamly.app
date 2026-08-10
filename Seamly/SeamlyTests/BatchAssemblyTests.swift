import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// The record→scroll→auto-stitch flow must produce a *correct* stitch on import: the captured
/// keyframes are re-ordered into scroll order and stitched, regardless of the order the extension
/// happened to write them (the on-device failure was frames stacked in the wrong order). This
/// exercises the real flow — `LibraryModel.refresh()` imports from the App Group and assembles.
@MainActor
struct BatchAssemblyTests {

    private func session(
        keyframes: [Keyframe],
        chrome: [KeyframeChrome]
    ) -> StitchSession {
        StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 2,
            orientation: .portrait,
            keyframes: keyframes,
            keyframeChrome: chrome
        )
    }

    /// A tall source with a monotonic vertical ramp (so scroll position is unambiguous) plus
    /// horizontal structure that survives downscaling.
    private func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func crop(_ image: CGImage, y: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
    }

    @Test func remapsPlannedChromeFromTemporaryIDsByKeyframeSlot() {
        let temporaryTopID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let temporaryBottomID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let storedTopID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let storedBottomID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let planned = session(
            keyframes: [
                Keyframe(id: temporaryTopID, filename: "kf-0", pixelWidth: 100, pixelHeight: 300, index: 0),
                Keyframe(id: temporaryBottomID, filename: "kf-1", pixelWidth: 100, pixelHeight: 300, index: 1),
            ],
            // Deliberately reverse record order: UUID ownership, not array position, resolves the
            // automatic value before slot identity is transferred to the persisted keyframe.
            chrome: [
                KeyframeChrome(keyframeID: temporaryBottomID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 12, bottom: 22), confidence: 0.8)),
                KeyframeChrome(keyframeID: temporaryTopID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 11, bottom: 21), confidence: 0.9)),
            ]
        )
        let stored = [
            Keyframe(id: storedTopID, filename: "top.bgra", pixelWidth: 100, pixelHeight: 300, index: 0),
            Keyframe(id: storedBottomID, filename: "bottom.bgra", pixelWidth: 100, pixelHeight: 300, index: 1),
        ]

        let remapped = StitchAssembler.remapKeyframeChrome(
            from: planned,
            onto: stored,
            preserving: []
        )

        #expect(remapped.map(\.keyframeID) == [storedTopID, storedBottomID])
        #expect(remapped[0].automatic?.insets == ChromeInsets(top: 11, bottom: 21))
        #expect(remapped[1].automatic?.insets == ChromeInsets(top: 12, bottom: 22))
    }

    @Test func replanningReplacesAutomaticChromeButPreservesOverridesByStoredIdentity() {
        let temporaryFirstID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let temporarySecondID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let storedAID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let storedBID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let planned = session(
            keyframes: [
                Keyframe(id: temporaryFirstID, filename: "kf-0", pixelWidth: 100, pixelHeight: 300, index: 0),
                Keyframe(id: temporarySecondID, filename: "kf-1", pixelWidth: 100, pixelHeight: 300, index: 1),
            ],
            chrome: [
                KeyframeChrome(keyframeID: temporaryFirstID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 31, bottom: 41), confidence: 0.7)),
                KeyframeChrome(keyframeID: temporarySecondID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 32, bottom: 42), confidence: 0.6)),
            ]
        )
        // Recovered scroll order is B then A. Overrides stay attached to the persisted image UUID,
        // while the fresh automatic measurements arrive by recovered slot.
        let reorderedStored = [
            Keyframe(id: storedBID, filename: "b.bgra", pixelWidth: 100, pixelHeight: 300, index: 0),
            Keyframe(id: storedAID, filename: "a.bgra", pixelWidth: 100, pixelHeight: 300, index: 1),
        ]
        let existing = [
            KeyframeChrome(
                keyframeID: storedAID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: 1, bottom: 2), confidence: 0.1),
                userOverride: ChromeOverride(top: 101)
            ),
            KeyframeChrome(
                keyframeID: storedBID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: 3, bottom: 4), confidence: 0.2),
                userOverride: ChromeOverride(bottom: 202)
            ),
        ]

        let remapped = StitchAssembler.remapKeyframeChrome(
            from: planned,
            onto: reorderedStored,
            preserving: existing
        )

        #expect(remapped[0] == KeyframeChrome(
            keyframeID: storedBID,
            automatic: ChromeMeasurement(insets: ChromeInsets(top: 31, bottom: 41), confidence: 0.7),
            userOverride: ChromeOverride(bottom: 202)
        ))
        #expect(remapped[1] == KeyframeChrome(
            keyframeID: storedAID,
            automatic: ChromeMeasurement(insets: ChromeInsets(top: 32, bottom: 42), confidence: 0.6),
            userOverride: ChromeOverride(top: 101)
        ))
    }

    @Test func remappingEmitsOnlyRecordsOwnedByFinalKeyframes() {
        let temporaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let danglingPlanID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let finalID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let danglingStoredID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let planned = session(
            keyframes: [Keyframe(id: temporaryID, filename: "kf-0", pixelWidth: 100, pixelHeight: 300, index: 0)],
            chrome: [
                KeyframeChrome(keyframeID: temporaryID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 10, bottom: 20), confidence: 0.9)),
                KeyframeChrome(keyframeID: danglingPlanID, automatic: ChromeMeasurement(insets: ChromeInsets(top: 99, bottom: 99), confidence: 0.9)),
            ]
        )
        let stored = [Keyframe(id: finalID, filename: "final.bgra", pixelWidth: 100, pixelHeight: 300, index: 0)]
        let existing = [
            KeyframeChrome(keyframeID: finalID, userOverride: ChromeOverride(top: 15)),
            KeyframeChrome(keyframeID: danglingStoredID, userOverride: ChromeOverride(bottom: 25)),
        ]

        let remapped = StitchAssembler.remapKeyframeChrome(
            from: planned,
            onto: stored,
            preserving: existing
        )

        #expect(remapped == [KeyframeChrome(
            keyframeID: finalID,
            automatic: ChromeMeasurement(insets: ChromeInsets(top: 10, bottom: 20), confidence: 0.9),
            userOverride: ChromeOverride(top: 15)
        )])
        #expect(Set(remapped.map(\.keyframeID)) == Set(stored.map(\.id)))
    }

    @Test func remappingKeepsARecordForAPlannedButUnmeasuredKeyframe() {
        let temporaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let finalID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let planned = session(
            keyframes: [Keyframe(id: temporaryID, filename: "kf-0", pixelWidth: 100, pixelHeight: 300, index: 0)],
            chrome: [KeyframeChrome(keyframeID: temporaryID)]
        )
        let stored = [Keyframe(id: finalID, filename: "final.bgra", pixelWidth: 100, pixelHeight: 300, index: 0)]

        let remapped = StitchAssembler.remapKeyframeChrome(
            from: planned,
            onto: stored,
            preserving: []
        )

        #expect(remapped == [KeyframeChrome(keyframeID: finalID)])
    }

    @Test func importReordersScrambledKeyframesAndStitches() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let group = root.appendingPathComponent("group", isDirectory: true)
        let app = root.appendingPathComponent("app", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: app, withIntermediateDirectories: true)

        // Three overlapping frames sliced from one source: top, mid, bottom (dy = 140 each).
        let W = 120, H = 360, D = 140
        let source = makeSource(width: W, height: H + 2 * D)   // 640 tall
        let frames = ["kf-top.bgra": crop(source, y: 0, height: H),
                      "kf-mid.bgra": crop(source, y: D, height: H),
                      "kf-bot.bgra": crop(source, y: 2 * D, height: H)]

        let id = UUID()
        let groupStore = SessionStore(containerURL: group)
        let folder = try groupStore.createFolder(for: id)
        for (name, image) in frames {
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
        }

        // Manifest lists keyframes in a SCRAMBLED order (mid, bot, top) with no usable geometry —
        // exactly what a mis-tracked capture leaves behind.
        let midID = UUID(), bottomID = UUID(), topID = UUID()
        var session = StitchSession(id: id, createdAt: Date(), status: .complete, deviceScale: 2, orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String)
        session.keyframes = [
            Keyframe(id: midID, filename: "kf-mid.bgra", pixelWidth: W, pixelHeight: H, index: 0),
            Keyframe(id: bottomID, filename: "kf-bot.bgra", pixelWidth: W, pixelHeight: H, index: 1),
            Keyframe(id: topID, filename: "kf-top.bgra", pixelWidth: W, pixelHeight: H, index: 2),
        ]
        session.keyframeChrome = [
            KeyframeChrome(keyframeID: midID, userOverride: ChromeOverride(top: 7)),
        ]
        try groupStore.writeManifest(session)

        let model = LibraryModel(appContainer: app, groupContainer: group)
        await model.refresh()

        #expect(model.captures.count == 1)
        let capture = try #require(model.captures.first)

        // Keyframes are now in true scroll order top→bottom.
        let order = capture.session.keyframes.sorted { $0.index < $1.index }.map(\.filename)
        #expect(order == ["kf-top.bgra", "kf-mid.bgra", "kf-bot.bgra"])
        let remappedMidChrome = try #require(capture.session.keyframeChrome.first { $0.keyframeID == midID })
        #expect(remappedMidChrome.userOverride == ChromeOverride(top: 7))
        #expect(capture.session.keyframeChrome.allSatisfy {
            Set(capture.session.keyframes.map(\.id)).contains($0.keyframeID)
        })
        #expect(capture.session.keyframeChromeValidationIssues().isEmpty)

        // And it assembled to the correct continuous height (H + 2·D), not three frames stacked.
        #expect(capture.phase == .ready)
        let proxy = try #require(capture.proxy)
        #expect(abs(proxy.height - (H + 2 * D)) <= 24)
    }
}
