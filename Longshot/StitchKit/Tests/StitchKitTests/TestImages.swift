import CoreGraphics
import Foundation

/// Helpers for building deterministic synthetic frames in tests. These stand in for
/// real screenshots: a tall reference image sliced at known offsets lets us assert the
/// stitching primitives recover exactly what we put in.
enum TestImages {
    /// An RGB image built by filling rectangles, described in the image's own
    /// top-left origin coordinate space (row 0 = top).
    ///
    /// A CGBitmapContext stores buffer row 0 at device `y = 0`, and `makeImage()` maps
    /// buffer rows straight to CGImage rows (row 0 = image top). So filling at device
    /// `y = 0` already lands at the image top — no flip needed here; `VerticalProfile`
    /// applies the one flip that keeps profile row 0 aligned with the image top.
    static func make(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx)
        return ctx.makeImage()!
    }

    /// A uniform gray image.
    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: gray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Top `topHeight` rows one gray, the rest another.
    static func horizontalSplit(width: Int, height: Int, topHeight: Int, topGray: CGFloat, bottomGray: CGFloat) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: bottomGray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(gray: topGray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: topHeight))
        }
    }

    /// Every row split left/right into two grays — high per-row horizontal variance.
    static func verticalSplit(width: Int, height: Int, leftGray: CGFloat, rightGray: CGFloat) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: rightGray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(gray: leftGray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
    }

    /// A tall image whose luminance increases smoothly top-to-bottom, drawn as
    /// `bands` horizontal stripes. Useful as a "content" reference to slice.
    static func verticalGradient(width: Int, height: Int, bands: Int = 64) -> CGImage {
        make(width: width, height: height) { ctx in
            let bandHeight = CGFloat(height) / CGFloat(bands)
            for i in 0..<bands {
                let g = CGFloat(i) / CGFloat(max(1, bands - 1))
                ctx.setFillColor(gray: g, alpha: 1)
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * bandHeight, width: CGFloat(width), height: bandHeight + 1))
            }
        }
    }

    /// Crop a sub-rectangle in top-left coordinates.
    static func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: x, y: y, width: width, height: height))!
    }
}
