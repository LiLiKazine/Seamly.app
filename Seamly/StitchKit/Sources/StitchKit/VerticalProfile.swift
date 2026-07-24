import CoreGraphics
import Accelerate

/// Reduces a full frame to a compact 1-D `FrameProfile`.
///
/// The frame is drawn — downscaled and luminance-converted in one step — into a small
/// grayscale bitmap (top-left origin), then each row's mean and horizontal variance are
/// computed with vDSP. Downscaling the width to `targetWidth` samples across the whole
/// row (covering left/mid/right), so the per-row statistics are cheap yet representative.
///
/// Matching runs on this grayscale signal with a fixed luminance conversion, which makes
/// it color-space-agnostic — color space only ever affects the final composited pixels.
public struct VerticalProfile: Sendable {
    /// Downscaled column count. Small enough to keep per-frame work tiny (so ReplayKit
    /// doesn't throttle delivery), large enough to capture horizontal structure.
    public let targetWidth: Int
    /// Cap on profile row count (vertical resolution). Height is decoupled from width: on a
    /// tall device frame (~2556 px) this holds `rowScale ≈ 4 px/row`, fine enough that a normal
    /// scroll of tens of px spans several rows and the matcher can resolve it. An aspect-locked
    /// height (`rowScale = sourceWidth/64 ≈ 18`) collapsed a 60 px scroll into ~3 rows — below
    /// the matcher's resolution — which is why real-screen stitching failed while 1:1-ish test
    /// fixtures passed.
    public let maxRows: Int

    public init(targetWidth: Int = 64, maxRows: Int = 640) {
        precondition(targetWidth > 0, "targetWidth must be positive")
        precondition(maxRows > 0, "maxRows must be positive")
        self.targetWidth = targetWidth
        self.maxRows = maxRows
    }

    /// Reduces `image` to a `FrameProfile`.
    ///
    /// By default the height is derived to preserve aspect ratio (cheap, coarse rows for
    /// the extension's provisional matching). Pass `forcingHeight: image.height` for the
    /// app's pixel-exact seam refinement, where one profile row must equal one source
    /// pixel so a recovered `dy` is pixel-accurate.
    public func profile(_ image: CGImage, forcingHeight: Int? = nil) -> FrameProfile {
        let sourceWidth = image.width
        let sourceHeight = image.height
        let width = min(targetWidth, sourceWidth)
        // Uniform vertical downscale (capped at `maxRows`) keeps rows evenly spaced, so
        // `rowScale` stays a single linear factor from profile row to source pixel — width and
        // height scale independently. The caller can pin the row count to full pixel resolution
        // (`forcingHeight`) for the app's pixel-exact seam refinement.
        let height = forcingHeight ?? min(sourceHeight, maxRows)

        guard let (buffer, bytesPerRow) = renderRGBA(image, width: width, height: height) else {
            return FrameProfile(rows: [], variances: [], sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        }

        var rows = [[Float]](repeating: [], count: height)
        var variances = [Float](repeating: 0, count: height)

        buffer.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            for row in 0..<height {
                let rowPtr = base + row * bytesPerRow
                // Fixed BT.601 luma from the RGBA samples. We compute luminance ourselves
                // rather than letting CoreGraphics convert to `DeviceGray`, whose gamma-managed
                // sRGB→gray conversion is unnecessary here and keeps the signal a plain,
                // predictable function of the source pixels.
                var signature = [Float](repeating: 0, count: width)
                for c in 0..<width {
                    let p = rowPtr + c * 4   // RGBA, 8-bit
                    let r = Float(p[0]), g = Float(p[1]), b = Float(p[2])
                    signature[c] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
                }
                let mean = vDSP.mean(signature)
                let meanSquare = vDSP.meanSquare(signature)
                rows[row] = signature
                variances[row] = max(0, meanSquare - mean * mean)
            }
        }

        return FrameProfile(rows: rows, variances: variances, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// Draws `image` into an 8-bit RGBA bitmap (sRGB) with a top-left origin and returns the
    /// pixel buffer plus its (possibly padded) bytes-per-row. The caller derives per-row luma.
    private func renderRGBA(_ image: CGImage, width: Int, height: Int) -> (Data, Int)? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // A CoreGraphics bitmap context has a bottom-left origin, so drawing a top-down CGImage
        // straight in already lands buffer row 0 at the image's TOP row (`makeImage`/readback
        // maps buffer row 0 to image row 0). No flip: an extra flip would invert profile row
        // order, turning a real downward scroll into an apparent upward one — which negated the
        // matched `dy`, so the tracker read every forward scroll as a back-scroll and skipped
        // it, shattering real captures while (differently-constructed) synthetic fixtures passed.
        // Nearest-neighbor: a low/linear filter blends adjacent rows, and the blend phase
        // differs between a crop and its parent image — which would make a keyframe's
        // profile disagree with the same region of another frame and defeat pixel-exact
        // refinement. .none keeps each profile row a faithful function of its source rows.
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = ctx.data else { return nil }
        let bytesPerRow = ctx.bytesPerRow
        let copy = Data(bytes: data, count: bytesPerRow * height)
        return (copy, bytesPerRow)
    }
}
