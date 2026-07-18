import Testing
import CoreVideo
import CoreGraphics
@testable import StitchKit

/// Locks down the direct `CVPixelBuffer` → `CGImage` decode used by the broadcast extension: it
/// must preserve orientation (buffer row 0 = image TOP) and channel order (32BGRA → RGB), because
/// the profiler/matcher geometry depends on top-down rows and a flip here would silently invert
/// every real capture (the exact class of bug that broke earlier device stitching).
struct PixelBufferImageTests {
    @Test func decodesTopDownWithCorrectChannels() throws {
        let width = 8, height = 8
        // Top half a distinct colour from the bottom half so a vertical flip is detectable, with
        // known B/G/R bytes so channel order is checkable.
        let top = (b: UInt8(200), g: UInt8(150), r: UInt8(100))
        let bottom = (b: UInt8(10), g: UInt8(20), r: UInt8(30))
        let pb = try #require(makeBGRABuffer(width: width, height: height, topHalf: top, bottomHalf: bottom))

        let image = try #require(PixelBufferImage.makeCGImage(from: pb))
        #expect(image.width == width)
        #expect(image.height == height)

        let topPixel = rgba(of: image, x: 0, y: 0)
        let bottomPixel = rgba(of: image, x: 0, y: height - 1)

        // Row 0 is the TOP colour, not the bottom — no vertical flip.
        #expect(close(topPixel.r, 100) && close(topPixel.g, 150) && close(topPixel.b, 200))
        #expect(close(bottomPixel.r, 30) && close(bottomPixel.g, 20) && close(bottomPixel.b, 10))
    }

    @Test func rejectsNonBGRA() throws {
        // A non-32BGRA buffer returns nil so the caller can fall back rather than misread bytes.
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32ARGB, nil, &pb)
        let buffer = try #require(pb)
        #expect(PixelBufferImage.makeCGImage(from: buffer) == nil)
    }

    // MARK: - Helpers

    private func makeBGRABuffer(width: Int, height: Int, topHalf: (b: UInt8, g: UInt8, r: UInt8), bottomHalf: (b: UInt8, g: UInt8, r: UInt8)) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let colour = y < height / 2 ? topHalf : bottomHalf
            for x in 0..<width {
                let p = ptr + y * bytesPerRow + x * 4
                p[0] = colour.b; p[1] = colour.g; p[2] = colour.r; p[3] = 255   // BGRA
            }
        }
        return buffer
    }

    private func rgba(of image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let i = (y * w + x) * 4
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
    }

    private func close(_ a: Int, _ b: Int, tolerance: Int = 3) -> Bool { abs(a - b) <= tolerance }
}
