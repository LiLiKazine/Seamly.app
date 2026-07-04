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

    /// Composite a session's keyframes into the full-resolution long image.
    nonisolated static func composite(_ session: StitchSession, in folder: URL, compositor: Compositor = Compositor()) throws -> CGImage {
        let cs = colorSpace(for: session)
        return try compositor.composite(session) { keyframe in
            try loadKeyframe(keyframe, in: folder, colorSpace: cs)
        }
    }

    /// Write a session's PDF to `url`.
    nonisolated static func writePDF(_ session: StitchSession, in folder: URL, to url: URL, compositor: Compositor = Compositor()) throws {
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
