import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// A per-pixel grayscale noise image: distinct rows with real horizontal variance, so the
/// matcher and refinement have structure to lock onto. Buffer row 0 = image top.
private func noise(width: Int, height: Int, seed: Int = 3) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let bpr = ctx.bytesPerRow
    ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
        for r in 0..<height {
            for c in 0..<width {
                let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
                let v = UInt8((n >> 7) & 0xFF)
                let i = r * bpr + c * 4
                p[i] = v; p[i + 1] = v; p[i + 2] = v; p[i + 3] = 255
            }
        }
    }
    return ctx.makeImage()!
}

/// Native-size grayscale bytes for pixel comparison.
private func grayBytes(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    let cs = CGColorSpaceCreateDeviceGray()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    return Array(UnsafeBufferPointer(start: p, count: w * h))
}

private func rgb(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let w = image.width, h = image.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    // This bitmap readback is bottom-first; flip y so callers can sample top-down.
    let i = (h - 1 - y) * w * 4 + x * 4
    return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
}

private func keyframe(_ index: Int, height: Int, width: Int) -> Keyframe {
    Keyframe(filename: "kf-\(index).heic", pixelWidth: width, pixelHeight: height, index: index)
}

/// Crop genuine-top rows `[top, top+height)` — `CGImage.cropping` is bottom-referenced.
private func topCrop(_ image: CGImage, x: Int = 0, top: Int, width: Int, height: Int) -> CGImage {
    image.cropping(to: CGRect(x: x, y: image.height - top - height, width: width, height: height))!
}

@Suite struct CompositorTests {
    let compositor = Compositor()

    @Test func reproducesReferencePixelsWithoutChrome() throws {
        let W = 120, H = 300
        let reference = noise(width: W, height: 900)
        let positions = [0, 200, 400, 600]
        var frames: [Int: CGImage] = [:]
        var keyframes: [Keyframe] = []
        var seams: [Seam] = []
        for (i, pos) in positions.enumerated() {
            frames[i] = topCrop(reference, top: pos, width: W, height: H)
            keyframes.append(keyframe(i, height: H, width: W))
            if i > 0 {
                // Provisional offset deliberately off by a few px — refinement must snap it.
                let perturb = [ -3, 2, -1 ][i - 1]
                seams.append(Seam(fromIndex: i - 1, provisionalDy: 200 + perturb, confidence: 0.8))
            }
        }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait, keyframes: keyframes, seams: seams)

        let out = try compositor.composite(session) { frames[$0.index]! }
        #expect(out.width == W)
        #expect(out.height == 900)

        let expected = grayBytes(reference)
        let actual = grayBytes(out)
        #expect(expected.count == actual.count)
        var maxDiff = 0
        for i in 0..<min(expected.count, actual.count) {
            maxDiff = max(maxDiff, abs(Int(expected[i]) - Int(actual[i])))
        }
        #expect(maxDiff <= 4)   // pixel-exact within rounding
    }

    @Test func singleKeyframeReproducesItself() throws {
        let img = noise(width: 100, height: 250)
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 2, orientation: .portrait,
                                    keyframes: [keyframe(0, height: 250, width: 100)])
        let out = try compositor.composite(session) { _ in img }
        #expect(out.width == 100)
        #expect(out.height == 250)
    }

    @Test func chromeAppearsOnceAtTopAndBottom() throws {
        let W = 100, H = 300, T = 20, B = 20
        let kf = TestImages.make(width: W, height: H) { ctx in
            ctx.setFillColor(gray: 0.5, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: T))          // top chrome red
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: H - B, width: W, height: B))      // bottom chrome blue
        }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: [keyframe(0, height: H, width: W), keyframe(1, height: H, width: W)],
                                    seams: [Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.7, chromeTopPixels: T, chromeBottomPixels: B)])
        let out = try compositor.composite(session) { _ in kf }
        #expect(out.height == (H - B) + 100 + B)   // 400
        #expect(rgb(out, x: 50, y: 5).r > 200)      // top chrome red
        #expect(rgb(out, x: 50, y: 200).g > 100)    // middle content gray/green channel present, not pure red/blue
        #expect(rgb(out, x: 50, y: out.height - 5).b > 200)  // bottom chrome blue
    }

    @Test func pdfPaginatesPastPageLimit() throws {
        let W = 120, H = 300
        let reference = noise(width: W, height: 900)
        var frames: [Int: CGImage] = [:]
        var keyframes: [Keyframe] = []
        var seams: [Seam] = []
        for (i, pos) in [0, 200, 400, 600].enumerated() {
            frames[i] = topCrop(reference, top: pos, width: W, height: H)
            keyframes.append(keyframe(i, height: H, width: W))
            if i > 0 { seams.append(Seam(fromIndex: i - 1, provisionalDy: 200, confidence: 0.8)) }
        }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait, keyframes: keyframes, seams: seams)
        let smallPage = Compositor(pdfPageHeightLimit: 400)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("longshot-test-\(keyframes.count).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try smallPage.writePDF(session, images: { frames[$0.index]! }, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let doc = CGPDFDocument(url as CFURL)
        #expect(doc != nil)
        #expect(doc!.numberOfPages == 3)   // 900 / 400 -> 3 pages
    }

    @Test func flagsHorizontalDriftSeam() throws {
        let reference = noise(width: 200, height: 600)
        let a = topCrop(reference, x: 0, top: 0, width: 150, height: 300)
        let b = topCrop(reference, x: 4, top: 100, width: 150, height: 300)  // shifted right 4px
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: [keyframe(0, height: 300, width: 150), keyframe(1, height: 300, width: 150)],
                                    seams: [Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8)])
        let refined = try compositor.refineSeams(session) { $0.index == 0 ? a : b }
        #expect(refined[0].isLowConfidence)
    }
}
