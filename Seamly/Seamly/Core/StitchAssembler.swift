import CoreGraphics
import Foundation
import StitchKit

/// Runs the heavy pixel compositing off the main actor. Pure, `Sendable` inputs/outputs so it
/// can hop threads freely.
enum StitchAssembler {
    /// Load a keyframe image, choosing raw vs. encoded by file extension.
    nonisolated static func loadKeyframe(_ keyframe: Keyframe, in folder: URL, colorSpace: CGColorSpace?) throws -> CGImage {
        let url = folder.appendingPathComponent(keyframe.filename)
        if url.pathExtension == "bgra" {
            return try KeyframeIO.readRaw(from: url, width: keyframe.pixelWidth, height: keyframe.pixelHeight, colorSpace: colorSpace)
        }
        return try KeyframeIO.read(from: url)
    }

    nonisolated static func colorSpace(for session: StitchSession) -> CGColorSpace? {
        session.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }
    }

    /// Re-derive scroll order and geometry for a session with `BatchStitcher`, using `strategy`
    /// to decide how much to trust the input order, and returning a corrected manifest. Run
    /// **once at import**: the extension's live-tracked order, seams, and bands are unreliable
    /// (the whole on-device failure), so we recover them from the keyframes themselves —
    /// reordering the keyframes into scroll order and replacing the seams, segment breaks, and
    /// content bands. All user-facing fields (trims, color space, status, id, timestamps) are
    /// preserved, so the corrected manifest still composites and edits normally.
    /// A session with fewer than two keyframes has nothing to reorder and is returned unchanged.
    nonisolated static func resolveGeometry(_ session: StitchSession, in folder: URL, strategy: BatchStitcher.OrderStrategy = .recover, stitcher: BatchStitcher = BatchStitcher()) throws -> StitchSession {
        guard session.keyframes.count > 1 else { return session }
        let ordered = session.keyframes.sorted { $0.index < $1.index }
        let cs = colorSpace(for: session)
        let images = try ordered.map { try loadKeyframe($0, in: folder, colorSpace: cs) }
        let plan = try stitcher.plan(images, strategy: strategy)

        var resolved = session
        // Reorder the real keyframes into scroll order, reindexing to match the recovered seams
        // (which are slot-based); keep each keyframe's filename/dims/id.
        resolved.keyframes = plan.order.enumerated().map { slot, srcIndex in
            var kf = ordered[srcIndex]
            kf.index = slot
            return kf
        }
        resolved.seams = plan.session.seams
        resolved.segmentBreaks = plan.session.segmentBreaks
        resolved.contentBands = plan.session.contentBands
        resolved.orderAssumed = plan.session.orderAssumed
        return resolved
    }

    /// Composite a session's keyframes into the full-resolution long image. The wider refinement
    /// window matches `BatchStitcher`'s: a provisional offset recovered from the downscaled
    /// profile can be a few source px off, more than the compositor's default ±6 at real geometry.
    nonisolated static func composite(_ session: StitchSession, in folder: URL, compositor: Compositor = Compositor(refinementDelta: 16)) throws -> CGImage {
        let cs = colorSpace(for: session)
        return try compositor.composite(session) { keyframe in
            try loadKeyframe(keyframe, in: folder, colorSpace: cs)
        }
    }

    /// Write a session's PDF to `url`.
    nonisolated static func writePDF(_ session: StitchSession, in folder: URL, to url: URL, compositor: Compositor = Compositor(refinementDelta: 16)) throws {
        let cs = colorSpace(for: session)
        try compositor.writePDF(session, images: { keyframe in
            try loadKeyframe(keyframe, in: folder, colorSpace: cs)
        }, to: url)
    }

    /// Downscale a composited image to a display proxy no taller than `maxHeight` — a GPU
    /// texture tops out ~16,384 px/side, so a full-res stitch can't render as one texture.
    nonisolated static func makeProxy(_ image: CGImage, maxHeight: Int = 4096) -> CGImage {
        guard image.height > maxHeight else { return image }
        let scale = Double(maxHeight) / Double(image.height)
        let w = max(1, Int(Double(image.width) * scale)), h = maxHeight
        // Downscale is best-effort: if the context can't be allocated or read back (effectively
        // only under memory pressure), fall back to the full-res image. It may exceed the GPU
        // texture limit and fail to render, but that's strictly better than crashing the display
        // path — and the failure surfaces visibly rather than as a silent wrong-size proxy.
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
