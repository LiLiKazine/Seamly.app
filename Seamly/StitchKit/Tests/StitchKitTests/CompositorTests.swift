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
    // Buffer row 0 is the image's TOP row (an unflipped bitmap readback reproduces image
    // order), so a top-down row `y` reads straight from buffer row `y`.
    let i = y * w * 4 + x * 4
    return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
}

private func keyframe(_ index: Int, height: Int, width: Int) -> Keyframe {
    Keyframe(filename: "kf-\(index).heic", pixelWidth: width, pixelHeight: height, index: index)
}

private func chromeRecord(_ keyframe: Keyframe, top: Int, bottom: Int, confidence: Double = 0.9) -> KeyframeChrome {
    KeyframeChrome(
        keyframeID: keyframe.id,
        automatic: ChromeMeasurement(insets: ChromeInsets(top: top, bottom: bottom), confidence: confidence)
    )
}

private func chromeRecords(_ keyframes: [Keyframe], top: Int, bottom: Int, confidence: Double = 0.9) -> [KeyframeChrome] {
    keyframes.map { chromeRecord($0, top: top, bottom: bottom, confidence: confidence) }
}

/// Crop genuine-top rows `[top, top+height)`. `CGImage.cropping` is top-referenced (y = 0 is
/// the image's top row), so a top-down `top` maps straight through.
private func topCrop(_ image: CGImage, x: Int = 0, top: Int, width: Int, height: Int) -> CGImage {
    image.cropping(to: CGRect(x: x, y: top, width: width, height: height))!
}

private struct Pixel: Equatable, CustomStringConvertible {
    var r: Int
    var g: Int
    var b: Int

    var description: String { "(\(r), \(g), \(b))" }
}

private let topChromePixel = Pixel(r: 255, g: 0, b: 0)
private let bottomChromePixel = Pixel(r: 0, g: 0, b: 255)

private func contentPixel(_ row: Int) -> Pixel {
    Pixel(r: row % 251, g: 96, b: (row * 7) % 251)
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> Pixel {
    let p = rgb(image, x: x, y: y)
    return Pixel(r: p.r, g: p.g, b: p.b)
}

/// A top-down exact RGBA fixture. Content rows encode their logical scroll-coordinate in
/// the pixel value; chrome rows use sentinel colours.
private func rowCodedFrame(width: Int, height: Int, topChrome: Int, bottomChrome: Int, contentBase: Int) -> CGImage {
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
    let bpr = ctx.bytesPerRow
    ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
        for y in 0..<height {
            let rowPixel: Pixel
            if y < topChrome {
                rowPixel = topChromePixel
            } else if y >= height - bottomChrome {
                rowPixel = bottomChromePixel
            } else {
                rowPixel = contentPixel(contentBase + y)
            }

            for x in 0..<width {
                let i = y * bpr + x * 4
                p[i] = UInt8(rowPixel.r)
                p[i + 1] = UInt8(rowPixel.g)
                p[i + 2] = UInt8(rowPixel.b)
                p[i + 3] = 255
            }
        }
    }
    return ctx.makeImage()!
}

private func expectRows(
    _ image: CGImage,
    topChrome: Int,
    contentRows: Range<Int>,
    bottomChrome: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(image.height == topChrome + contentRows.count + bottomChrome, sourceLocation: sourceLocation)

    for y in 0..<topChrome {
        #expect(pixel(image, x: 0, y: y) == topChromePixel, "top chrome row \(y)", sourceLocation: sourceLocation)
    }

    for (offset, contentRow) in contentRows.enumerated() {
        let y = topChrome + offset
        #expect(pixel(image, x: 0, y: y) == contentPixel(contentRow), "content row \(contentRow) at output row \(y)", sourceLocation: sourceLocation)
    }

    let bottomStart = topChrome + contentRows.count
    for y in bottomStart..<image.height {
        #expect(pixel(image, x: 0, y: y) == bottomChromePixel, "bottom chrome row \(y)", sourceLocation: sourceLocation)
    }
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

    @Test func globalTrimCropsTopAndBottom() throws {
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
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: keyframes, seams: seams, topTrim: 50, bottomTrim: 80)
        let out = try compositor.composite(session) { frames[$0.index]! }
        #expect(out.height == 900 - 50 - 80)
        #expect(out.width == W)
    }

    @Test func singleKeyframeReproducesItself() throws {
        let img = noise(width: 100, height: 250)
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 2, orientation: .portrait,
                                    keyframes: [keyframe(0, height: 250, width: 100)])
        let out = try compositor.composite(session) { _ in img }
        #expect(out.width == 100)
        #expect(out.height == 250)
    }

    @Test func cropsChromeOnceUsingPerKeyframeChromeAcrossManyKeyframes() throws {
        let W = 100, H = 300, T = 20, B = 20
        // Chromed frame: red top band, blue bottom band, a per-row content ramp between.
        let kf = TestImages.make(width: W, height: H) { ctx in
            for y in T..<(H - B) {
                let g = CGFloat((y * 7) % 200) / 255
                ctx.setFillColor(gray: g, alpha: 1); ctx.fill(CGRect(x: 0, y: y, width: W, height: 1))
            }
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: T))      // top red
            ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: H - B, width: W, height: B))  // bottom blue
        }
        // Four keyframes (>2): per-keyframe chrome must be cropped from every intermediate frame,
        // not just inferred once for the segment.
        let keyframes = (0..<4).map { keyframe($0, height: H, width: W) }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: keyframes,
                                    seams: (0..<3).map { Seam(fromIndex: $0, provisionalDy: 100, confidence: 0.7) },
                                    keyframeChrome: chromeRecords(keyframes, top: T, bottom: B))
        let out = try compositor.composite(session) { _ in kf }
        #expect(out.height == (H - B) + 100 * 3 + B)   // top chrome + 3 advances + bottom chrome

        // Red appears only in the top band and blue only in the bottom band — chrome once,
        // not restamped at each of the three interior seams.
        let reds = (0..<out.height).filter { let p = rgb(out, x: 50, y: $0); return p.r > 200 && p.b < 80 }
        let blues = (0..<out.height).filter { let p = rgb(out, x: 50, y: $0); return p.b > 200 && p.r < 80 }
        #expect(!reds.isEmpty && reds.allSatisfy { $0 < T + 4 })
        #expect(!blues.isEmpty && blues.allSatisfy { $0 > out.height - B - 4 })
    }

    @Test func missingSeamFallbackDoesNotStackFullFrame() throws {
        let W = 100, H = 300, T = 20, B = 20
        let reference = noise(width: W, height: 900)
        var frames: [Int: CGImage] = [:]
        for (i, pos) in [0, 100, 200].enumerated() { frames[i] = topCrop(reference, top: pos, width: W, height: H) }
        // Three keyframes but only the FIRST seam is recorded; the second is missing.
        let keyframes = (0..<3).map { keyframe($0, height: H, width: W) }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: keyframes,
                                    seams: [Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8)],
                                    keyframeChrome: chromeRecords(keyframes, top: T, bottom: B))
        let out = try compositor.composite(session) { frames[$0.index]! }
        let visibleContentHeight = H - T - B
        // The old fallback drew a whole visible content window for the missing seam (stacking); the
        // median-of-known-offsets fallback draws only ~100 rows.
        #expect(out.height < (H - B) + 100 + visibleContentHeight + B)     // did not stack a full frame
        #expect(out.height == (H - B) + 100 + 100 + B)          // fallback == median(known dys) == 100
    }

    @Test func expandedToCollapsedBottomChromeAddsExposedContentWithoutGapsOrDuplicates() throws {
        let W = 4, H = 20, T = 2, expandedBottom = 6, collapsedBottom = 2, dy = 5
        let keyframes = (0..<2).map { keyframe($0, height: H, width: W) }
        let frames = [
            0: rowCodedFrame(width: W, height: H, topChrome: T, bottomChrome: expandedBottom, contentBase: 0),
            1: rowCodedFrame(width: W, height: H, topChrome: T, bottomChrome: collapsedBottom, contentBase: dy),
        ]
        let session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            deviceScale: 3,
            orientation: .portrait,
            keyframes: keyframes,
            seams: [Seam(fromIndex: 0, provisionalDy: dy, confidence: 0.9)],
            keyframeChrome: [
                chromeRecord(keyframes[0], top: T, bottom: expandedBottom),
                chromeRecord(keyframes[1], top: T, bottom: collapsedBottom),
            ]
        )

        let out = try Compositor(refinementDelta: 0).composite(session) { frames[$0.index]! }

        // Previous content bottom is 14, current content bottom is 18, so the current
        // frame contributes rows 9..<18: content coordinates 14..<23.
        #expect(out.height == H + dy)
        expectRows(out, topChrome: T, contentRows: T..<23, bottomChrome: collapsedBottom)
    }

    @Test func collapsedToExpandedBottomChromeOmitsCoveredContentWithoutGapsOrDuplicates() throws {
        let W = 4, H = 20, T = 2, collapsedBottom = 2, expandedBottom = 6, dy = 5
        let keyframes = (0..<2).map { keyframe($0, height: H, width: W) }
        let frames = [
            0: rowCodedFrame(width: W, height: H, topChrome: T, bottomChrome: collapsedBottom, contentBase: 0),
            1: rowCodedFrame(width: W, height: H, topChrome: T, bottomChrome: expandedBottom, contentBase: dy),
        ]
        let session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            deviceScale: 3,
            orientation: .portrait,
            keyframes: keyframes,
            seams: [Seam(fromIndex: 0, provisionalDy: dy, confidence: 0.9)],
            keyframeChrome: [
                chromeRecord(keyframes[0], top: T, bottom: collapsedBottom),
                chromeRecord(keyframes[1], top: T, bottom: expandedBottom),
            ]
        )

        let out = try Compositor(refinementDelta: 0).composite(session) { frames[$0.index]! }

        // Previous content bottom is 18, current content bottom is 14, so the current
        // frame contributes rows 13..<14: content coordinate 18 only; newly covered rows
        // 14..<18 are not duplicated underneath the expanded bottom chrome.
        #expect(out.height == H + dy)
        expectRows(out, topChrome: T, contentRows: T..<19, bottomChrome: expandedBottom)
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamly-test-\(keyframes.count).pdf")
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

    /// Implausible per-keyframe chrome must not be clamped into a plausible-looking collapse.
    ///
    /// Before the guard, `band = max(1, h - top - bottom)` degraded to 1 and every seam was
    /// clamped to a 1px advance, so four 300px frames at dy=200 composited to 302px instead of
    /// 900 — with no throw, no log, and a manifest that still read as healthy. Refusing the band
    /// crops nothing instead: the chrome repeats, which is visible, rather than the content
    /// disappearing, which isn't.
    @Test func implausibleKeyframeChromeResolvesUnlockedRatherThanCollapsingTheStitch() throws {
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
        // Absurd: 290 of 300 rows declared chrome, leaving a 10px content band.
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: keyframes, seams: seams,
                                    keyframeChrome: chromeRecords(keyframes, top: 290, bottom: 0))

        let out = try compositor.composite(session) { frames[$0.index]! }
        // Cropping nothing reproduces the full scroll extent, exactly as `.unlocked` would.
        #expect(out.height == 900)
        #expect(out.width == W)
    }

    /// The ceiling is a floor for *rejection*, not a crop budget: a large-but-credible band is
    /// still honoured, so the guard can't quietly disable chrome cropping on real captures.
    @Test func largeButPlausibleKeyframeChromeIsStillCropped() throws {
        let W = 120, H = 300, T = 60, B = 40   // 100 of 300 rows = 33%, under the 50% ceiling
        let reference = noise(width: W, height: 900)
        var frames: [Int: CGImage] = [:]
        var keyframes: [Keyframe] = []
        var seams: [Seam] = []
        for (i, pos) in [0, 200, 400, 600].enumerated() {
            frames[i] = topCrop(reference, top: pos, width: W, height: H)
            keyframes.append(keyframe(i, height: H, width: W))
            if i > 0 { seams.append(Seam(fromIndex: i - 1, provisionalDy: 200, confidence: 0.8)) }
        }
        let session = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 3, orientation: .portrait,
                                    keyframes: keyframes, seams: seams,
                                    keyframeChrome: chromeRecords(keyframes, top: T, bottom: B))

        let out = try compositor.composite(session) { frames[$0.index]! }
        // First strip keeps top chrome and drops bottom chrome, each later strip advances dy,
        // and the final bottom chrome is re-added once.
        #expect(out.height == (H - B) + 3 * 200 + B)
    }

    @Test func chromePlausibilityRejectsOnlyInsetsThatLeaveNoSafeContent() {
        #expect(ChromeInsets(top: 20, bottom: 20).isPlausible(forPixelHeight: 300))
        #expect(ChromeInsets(top: 150, bottom: 0).isPlausible(forPixelHeight: 300))   // exactly at the ceiling
        #expect(!ChromeInsets(top: 151, bottom: 0).isPlausible(forPixelHeight: 300))
        #expect(!ChromeInsets(top: 361, bottom: 0).isPlausible(forPixelHeight: 360))  // the observed collapse
        #expect(ChromeInsets.zero.isPlausible(forPixelHeight: 300))
        #expect(!ChromeInsets(top: 0, bottom: 0).isPlausible(forPixelHeight: 0))      // no frame, no verdict
    }
}
