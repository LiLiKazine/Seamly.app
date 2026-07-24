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
        var session = StitchSession(id: id, createdAt: Date(), status: .complete, deviceScale: 2, orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String)
        session.keyframes = [
            Keyframe(filename: "kf-mid.bgra", pixelWidth: W, pixelHeight: H, index: 0),
            Keyframe(filename: "kf-bot.bgra", pixelWidth: W, pixelHeight: H, index: 1),
            Keyframe(filename: "kf-top.bgra", pixelWidth: W, pixelHeight: H, index: 2),
        ]
        try groupStore.writeManifest(session)

        let model = LibraryModel(appContainer: app, groupContainer: group)
        await model.refresh()

        #expect(model.captures.count == 1)
        let capture = try #require(model.captures.first)

        // Keyframes are now in true scroll order top→bottom.
        let order = capture.session.keyframes.sorted { $0.index < $1.index }.map(\.filename)
        #expect(order == ["kf-top.bgra", "kf-mid.bgra", "kf-bot.bgra"])

        // And it assembled to the correct continuous height (H + 2·D), not three frames stacked.
        #expect(capture.phase == .ready)
        let proxy = try #require(capture.proxy)
        #expect(abs(proxy.height - (H + 2 * D)) <= 24)
    }
}
