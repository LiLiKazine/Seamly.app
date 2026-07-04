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

    public init(targetWidth: Int = 64) {
        precondition(targetWidth > 0, "targetWidth must be positive")
        self.targetWidth = targetWidth
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
        // Preserve aspect ratio so profile rows map linearly back to source pixels,
        // unless the caller pins the row count to full pixel resolution.
        let height = forcingHeight ?? max(1, Int((Double(sourceHeight) * Double(width) / Double(sourceWidth)).rounded()))

        guard let (buffer, bytesPerRow) = renderGray(image, width: width, height: height) else {
            return FrameProfile(means: [], variances: [], sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        }

        var means = [Float](repeating: 0, count: height)
        var variances = [Float](repeating: 0, count: height)
        var rowFloats = [Float](repeating: 0, count: width)

        buffer.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            for row in 0..<height {
                let rowPtr = base + row * bytesPerRow
                vDSP.convertElements(of: UnsafeBufferPointer(start: rowPtr, count: width), to: &rowFloats)
                // Normalize 0...255 -> 0...1.
                var scaled = [Float](repeating: 0, count: width)
                vDSP.divide(rowFloats, 255.0, result: &scaled)
                let mean = vDSP.mean(scaled)
                let meanSquare = vDSP.meanSquare(scaled)
                means[row] = mean
                variances[row] = max(0, meanSquare - mean * mean)
            }
        }

        return FrameProfile(means: means, variances: variances, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// Draws `image` into an 8-bit device-gray bitmap with a top-left origin and returns
    /// the pixel buffer plus its (possibly padded) bytes-per-row.
    private func renderGray(_ image: CGImage, width: Int, height: Int) -> (Data, Int)? {
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Flip so buffer row 0 is the top of the image (content-space top-down).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
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
