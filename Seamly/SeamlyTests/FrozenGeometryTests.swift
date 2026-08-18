import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Freezing moves seam refinement out of the draw path and into import, so the manifest becomes
/// the authority on geometry. That is what lets a user's hand-made alignment survive — and it is
/// only safe if it changes nothing else, which is what these pin.
struct FrozenGeometryTests {

    // MARK: - Helpers

    /// A tall source with a monotonic vertical ramp (so scroll position is unambiguous) plus
    /// horizontal structure that survives downscaling. Same shape as `BatchAssemblyTests`.
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
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func crop(_ image: CGImage, y: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("frozen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Write `images` as raw keyframes into `folder` and return a manifest referencing them.
    private func stage(_ images: [CGImage], in folder: URL) throws -> StitchSession {
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            colorSpaceName: images[0].colorSpace?.name as String?
        )
        for (i, image) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i)
            )
        }
        return session
    }

    private func loader(_ session: StitchSession, _ folder: URL) -> (Keyframe) throws -> CGImage {
        let cs = StitchAssembler.colorSpace(for: session)
        return { try StitchAssembler.loadKeyframe($0, in: folder, colorSpace: cs) }
    }

    private func pixelsAreIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return false }
        return (da as Data) == (db as Data)
    }

    /// The three `Screenshots` fixtures, full resolution (1320×2868), in scroll order. Real
    /// pixels: a synthetic ramp has one unambiguous score minimum, which is exactly the property
    /// that let a green synthetic suite hide a real bug here three times.
    private func realScreenshots() throws -> [CGImage] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // SeamlyTests
            .deletingLastPathComponent()            // Seamly
            .appendingPathComponent("StitchKit/Tests/StitchKitTests/Fixtures/Screenshots")
        return try ["IMG_1757.PNG", "IMG_1758.PNG", "IMG_1759.PNG"].map {
            try KeyframeIO.read(from: dir.appendingPathComponent($0))
        }
    }

    // MARK: - Tests

    /// The contract: a stored offset that is wrong by less than the refinement window is corrected
    /// to the pixel-exact value and *persisted*, instead of being corrected invisibly on every draw.
    @Test func freezingCorrectsAStoredOffsetToThePixelExactValue() throws {
        let folder = try temporaryFolder()
        let source = makeSource(width: 240, height: 1200)
        let trueDy = 300
        var session = try stage([crop(source, y: 0, height: 600), crop(source, y: trueDy, height: 600)], in: folder)
        session.seams = [Seam(fromIndex: 0, provisionalDy: trueDy + 9, confidence: 0.5)]

        let frozen = try StitchAssembler.freezeGeometry(session, in: folder)

        #expect(frozen.seams[0].provisionalDy == trueDy)
        // Everything the planner decided about this seam is left alone, so no user-facing wording
        // shifts as a side effect of freezing.
        #expect(frozen.seams[0].confidence == 0.5)
        #expect(frozen.seams[0].isLowConfidence == false)
    }

    /// The property repair depends on: once frozen, the draw path uses the stored number verbatim.
    /// Output height is a direct read-out of the offset used — with no chrome, a two-frame strip is
    /// `upperHeight + dy` tall — so a re-derived offset would change it.
    @Test func theDrawPathUsesTheStoredOffsetVerbatim() throws {
        let folder = try temporaryFolder()
        let source = makeSource(width: 240, height: 1200)
        var session = try stage([crop(source, y: 0, height: 600), crop(source, y: 300, height: 600)], in: folder)
        // Deliberately not the right answer, and deliberately inside the ±16 window that the old
        // draw path would have "corrected".
        session.seams = [Seam(fromIndex: 0, provisionalDy: 291, confidence: 0.5)]

        let image = try StitchAssembler.composite(session, in: folder)

        #expect(image.height == 600 + 291)
    }

    /// The whole safety argument for moving refinement: today's image is `refine(stored)`, and the
    /// new path is `composite(freeze(stored))` with refinement disabled. Same function, same
    /// inputs, so the bytes must match. On real pixels, because this is precisely where synthetic
    /// fixtures have lied before.
    @Test func freezingThenDrawingMatchesRefiningWhileDrawing() throws {
        let folder = try temporaryFolder()
        let base = try stage(try realScreenshots(), in: folder)
        let coarse = try StitchAssembler.resolveGeometry(base, in: folder, strategy: .recoverOrInputOrder)
        let load = loader(coarse, folder)

        let today = try Compositor(refinementDelta: 16).composite(coarse, images: load)
        let frozen = try StitchAssembler.freezeGeometry(coarse, in: folder)
        let now = try Compositor(refinementDelta: 0).composite(frozen, images: load)

        #expect(pixelsAreIdentical(today, now))
    }

    /// The call site: an import must leave a frozen manifest on disk, or every capture silently
    /// composites from coarse offsets. Compared against the same reference image as above.
    @Test func importingThroughMediaImporterLeavesAFrozenManifest() throws {
        let container = try temporaryFolder()
        let store = SessionStore(containerURL: container)
        let diag = Diagnostics(containerURL: nil, category: .app)
        let images = try realScreenshots()

        let id = try MediaImporter.write(
            images: images, into: store, strategy: .recoverOrInputOrder, source: .photos, diag: diag
        )
        let stored = try store.readManifest(for: id)
        let imported = try StitchAssembler.composite(stored, in: store.folder(for: id))

        let reference = try temporaryFolder()
        let base = try stage(images, in: reference)
        let coarse = try StitchAssembler.resolveGeometry(base, in: reference, strategy: .recoverOrInputOrder)
        let expected = try Compositor(refinementDelta: 16).composite(coarse, images: loader(coarse, reference))

        #expect(pixelsAreIdentical(imported, expected))
    }
}
