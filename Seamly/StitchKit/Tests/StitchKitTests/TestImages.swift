import CoreGraphics
import Foundation

/// Helpers for building deterministic synthetic frames in tests. These stand in for
/// real screenshots: a tall reference image sliced at known offsets lets us assert the
/// stitching primitives recover exactly what we put in.
enum TestImages {
    /// An RGB image built by filling rectangles, described in the image's own
    /// **top-left** origin coordinate space (row 0 = top), matching how real captured frames
    /// (from `CGImageSource`/`KeyframeIO.readRaw`) are oriented.
    ///
    /// A CGBitmapContext has a bottom-left origin, so we flip it: after the flip, filling at
    /// `y = 0` lands at the image's TOP row. This makes synthetic fixtures share the real
    /// frames' orientation, so `VerticalProfile` (which does not flip) maps a fixture's visual
    /// top to profile row 0 — the same as a real screenshot. (Previously `make` drew unflipped
    /// and `VerticalProfile` flipped to compensate; that double-flip agreed for synthetic
    /// fixtures but inverted real top-down frames, which is why on-device captures stitched
    /// upside-down / shattered.)
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
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
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

    /// Crop a sub-rectangle in **top-left** coordinates (`y = 0` is the image top), matching
    /// `make`'s top-down orientation. `CGImage.cropping` is itself top-referenced (`y = 0` is the
    /// image's top row), so the top-down `y` maps straight through — no conversion.
    static func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) -> CGImage {
        return image.cropping(to: CGRect(x: x, y: y, width: width, height: height))!
    }
}
