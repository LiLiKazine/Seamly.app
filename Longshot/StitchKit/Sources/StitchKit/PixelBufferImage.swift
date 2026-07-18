import CoreVideo
import CoreGraphics

/// Converts a ReplayKit video frame (a 32BGRA `CVPixelBuffer`) into a standalone `CGImage`
/// **without Core Image or the GPU**.
///
/// The broadcast extension has a hard ~50 MB footprint ceiling. Decoding each full-resolution
/// frame through a GPU `CIContext` (`CIImage` → `createCGImage`) spiked the footprint to ~47 MB
/// per frame — enough for the OS to suspend and then silently kill the extension before it could
/// call `broadcastFinished`. Wrapping the pixel buffer's own memory in a bitmap context and
/// copying it out once (`makeImage`) keeps the peak at roughly one frame's worth of bytes.
///
/// Orientation and channel order are chosen to match the previous `CIImage` path exactly, so the
/// downstream profiler/matcher geometry (which took several iterations to get right) is unchanged:
/// buffer row 0 stays the image's **top** row, and B/G/R/A memory maps to an RGB image.
public enum PixelBufferImage {
    /// A top-left-origin `CGImage` copied out of `pixelBuffer`, or `nil` if it isn't the expected
    /// 32BGRA format or a context can't be created (caller falls back / skips the frame).
    public static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // 32BGRA in memory (B,G,R,A) is CoreGraphics' premultiplied-first + little-endian layout.
        // sRGB matches screen content and the profiler's own sRGB render, so keyframe colors and
        // luma stay faithful to what the previous path produced.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // `makeImage` copies the pixels into an independent image, so it stays valid after the
        // base address is unlocked and the pixel buffer is released back to ReplayKit.
        return ctx.makeImage()
    }
}
