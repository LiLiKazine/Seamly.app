import CoreGraphics
import Foundation
import StitchKit

/// How `resolveGeometry` decides scroll order.
///
/// The choice is really "how much do we trust the order the images arrived in?", and that
/// depends entirely on where they came from — a photo pick order is a user's guess, while a
/// broadcast's or a video's is a timeline.
///
/// Note the fallback never *merges* anything. It only stops re-ordering: the assumed-order path
/// still runs `BatchStitcher.segmentsAlong`, which re-tests each consecutive pair for overlap and
/// breaks where there is none. Measured on the real device fixtures — `wechat-*` (home screen →
/// launch animation → chat list, genuinely non-overlapping) keeps its breaks after 0, 1 and 3
/// under every strategy here.
enum OrderStrategy {
    /// Recover order from pixel overlap; never fall back.
    ///
    /// Now unused by the shipping import paths. Kept for callers that have no meaningful input
    /// order at all — with one, `.recoverOrInputOrder` strictly dominates this, since it does the
    /// same recovery first and only differs when that recovery is not trustworthy.
    case recover
    /// Recover; if the result isn't one unbroken chain, fall back to the input order and mark
    /// `orderAssumed`. Used by "From Photos" and by broadcast import.
    ///
    /// A break is the only thing that makes the recovered order a guess — see `resolveGeometry`
    /// for why a low-confidence *seam* is not, and what it cost when it was treated as one.
    case recoverOrInputOrder
    /// Trust the input order verbatim (capture/temporal order). Used by "From Video".
    case inputOrder
}

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
    nonisolated static func resolveGeometry(_ session: StitchSession, in folder: URL, strategy: OrderStrategy = .recover, stitcher: BatchStitcher = BatchStitcher()) throws -> StitchSession {
        guard session.keyframes.count > 1 else { return session }
        let ordered = session.keyframes.sorted { $0.index < $1.index }
        let cs = colorSpace(for: session)
        let images = try ordered.map { try loadKeyframe($0, in: folder, colorSpace: cs) }
        let identity = Array(0..<images.count)

        let plan: BatchStitcher.Plan
        var orderAssumed = false
        switch strategy {
        case .recover:
            plan = try stitcher.plan(images)
        case .inputOrder:
            plan = try stitcher.plan(images, assumingOrder: identity)
        case .recoverOrInputOrder:
            let recovered = try stitcher.plan(images)
            // Only a segment break is evidence about *ordering*. Components that recovery could
            // not relate are placed by input index — a guess — so there the caller's guess is the
            // better one, and that is what the fallback is for.
            //
            // This used to also require every seam to clear `isLowConfidence`, which cost the
            // Photos path its whole reason to exist. Seam confidence is a statement about one
            // seam's *offset*, not about the order, and the fallback re-measures that same pair
            // with the same matcher — so a fuzzy seam stays exactly as fuzzy while a correctly
            // recovered order is thrown away. Measured on `Fixtures/Screenshots`: recovery nails
            // that six-screenshot set from any permutation, yet its seam 2→3 scores 0.368, so
            // every import fell back. With the photos picked in scroll order the fallback is a
            // no-op and nothing looks wrong, which is why this only surfaced as "stitching works
            // in order, shatters out of order" (`PhotoPickOrderTests`).
            let clean = recovered.session.segmentBreaks.isEmpty
            if clean {
                plan = recovered
            } else {
                plan = try stitcher.plan(images, assumingOrder: identity)
                orderAssumed = true
            }
        }

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
        resolved.orderAssumed = orderAssumed
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
