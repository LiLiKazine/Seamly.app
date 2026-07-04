import CoreGraphics
import Accelerate
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Assembles saved keyframes plus their manifest into the final long image.
///
/// For each seam it snaps the extension's provisional offset to pixel precision with a
/// small full-resolution local search, then draws the first frame with its top chrome,
/// each subsequent frame's newly-revealed content via a hard cut (no feathering — the
/// overlapping pixels are identical), and the last frame's bottom chrome. Output is a
/// `CGImage` (raster) or an incrementally-drawn `CGContext` PDF, in the source color space.
public struct Compositor: Sendable {
    public enum CompositorError: Error, Equatable {
        case noKeyframes
        case contextFailure
    }

    private let matcher: OffsetMatcher
    private let profiler: VerticalProfile
    /// ± pixels searched around each provisional offset during refinement.
    public let refinementDelta: Int
    /// Refined-match confidence below which we keep the provisional offset.
    public let refinementConfidence: Double
    /// Marker band height (px) drawn between segments in the raster path.
    public let separatorHeight: Int
    /// Max page height (points) for the PDF path before paginating.
    public let pdfPageHeightLimit: Int

    public init(
        matcher: OffsetMatcher = OffsetMatcher(minimumOverlap: 8),
        profiler: VerticalProfile = VerticalProfile(targetWidth: 64),
        refinementDelta: Int = 6,
        refinementConfidence: Double = 0.3,
        separatorHeight: Int = 8,
        pdfPageHeightLimit: Int = 14_400
    ) {
        self.matcher = matcher
        self.profiler = profiler
        self.refinementDelta = refinementDelta
        self.refinementConfidence = refinementConfidence
        self.separatorHeight = separatorHeight
        self.pdfPageHeightLimit = pdfPageHeightLimit
    }

    // MARK: - Public API

    /// Snap each seam's provisional offset to pixel precision, and flag seams with a
    /// nonzero horizontal component or a low-confidence vertical match.
    public func refineSeams(_ session: StitchSession, images: (Keyframe) throws -> CGImage) throws -> [Seam] {
        let byIndex = Dictionary(uniqueKeysWithValues: session.keyframes.map { ($0.index, $0) })
        return try session.seams.map { seam in
            guard let a = byIndex[seam.fromIndex], let b = byIndex[seam.fromIndex + 1] else { return seam }
            let imgA = try images(a), imgB = try images(b)
            let (dy, confident) = refineVertical(imgA, imgB, provisional: seam.provisionalDy)
            let dx = measureHorizontal(imgA, imgB, dy: dy)
            var refined = seam
            refined.provisionalDy = dy
            refined.provisionalDx = dx
            refined.isLowConfidence = seam.isLowConfidence || !confident || abs(dx) >= 2
            return refined
        }
    }

    /// Composite to a single raster `CGImage`.
    public func composite(_ session: StitchSession, images: (Keyframe) throws -> CGImage) throws -> CGImage {
        guard !session.keyframes.isEmpty else { throw CompositorError.noKeyframes }
        let refined = try refineSeams(session, images: images)
        let layout = try plan(session, refinedSeams: refined, images: images)
        let colorSpace = try firstImage(session, images).colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return try renderRaster(layout.pieces, width: layout.width, height: layout.totalHeight, colorSpace: colorSpace, images: images)
    }

    /// Render a set of pieces (destination Ys relative to the strip top) into one raster.
    /// The context is *not* flipped: an unflipped bitmap context reproduces a drawn CGImage
    /// upright and `makeImage()` returns it top-left — the flipped path mirrors it.
    private func renderRaster(_ pieces: [Piece], width: Int, height: Int, colorSpace: CGColorSpace, images: (Keyframe) throws -> CGImage) throws -> CGImage {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CompositorError.contextFailure }
        ctx.interpolationQuality = .none
        for piece in pieces {
            drawStrip(piece, srcRow: piece.srcY, height: piece.height, destY: piece.destY, in: ctx, images: images)
        }
        guard let image = ctx.makeImage() else { throw CompositorError.contextFailure }
        return image
    }

    /// Composite to a PDF at `url`, drawing keyframe strips incrementally (memory-safe,
    /// not bound by the GPU texture limit) and paginating past the viewer ceiling.
    public func writePDF(_ session: StitchSession, images: (Keyframe) throws -> CGImage, to url: URL) throws {
        guard !session.keyframes.isEmpty else { throw CompositorError.noKeyframes }
        let refined = try refineSeams(session, images: images)
        let layout = try plan(session, refinedSeams: refined, images: images)

        let colorSpace = try firstImage(session, images).colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var mediaBox = CGRect(x: 0, y: 0, width: layout.width, height: min(pdfPageHeightLimit, max(1, layout.totalHeight)))
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CompositorError.contextFailure
        }

        // Paginate each segment independently; a segment break starts a new page. Each page
        // is rasterized once (bounded by the page-height limit) then placed into the PDF.
        for segment in layout.segments {
            var drawn = 0
            while drawn < segment.height {
                let pageHeight = min(pdfPageHeightLimit, segment.height - drawn)
                let window = drawn..<(drawn + pageHeight)
                let pagePieces = clip(segment.pieces, to: window)
                let pageImage = try renderRaster(pagePieces, width: layout.width, height: pageHeight, colorSpace: colorSpace, images: images)
                var box = CGRect(x: 0, y: 0, width: layout.width, height: pageHeight)
                ctx.beginPage(mediaBox: &box)
                ctx.interpolationQuality = .none
                // PDF space is bottom-left (unlike bitmap readback); flip so the top-left
                // raster page lands upright in the document.
                ctx.saveGState()
                ctx.translateBy(x: 0, y: CGFloat(pageHeight))
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(pageImage, in: CGRect(x: 0, y: 0, width: layout.width, height: pageHeight))
                ctx.restoreGState()
                ctx.endPage()
                drawn += pageHeight
            }
        }
        ctx.closePDF()
    }

    /// Re-slice segment pieces to a page window, with destination Ys relative to the page.
    private func clip(_ pieces: [Piece], to window: Range<Int>) -> [Piece] {
        pieces.compactMap { piece in
            let lo = max(piece.segmentLocalY, window.lowerBound)
            let hi = min(piece.segmentLocalY + piece.height, window.upperBound)
            guard hi > lo else { return nil }
            return Piece(
                keyframe: piece.keyframe,
                srcY: piece.srcY + (lo - piece.segmentLocalY),
                height: hi - lo,
                destY: lo - window.lowerBound,
                segmentLocalY: 0
            )
        }
    }

    // MARK: - Layout

    /// One source strip: rows `[srcY, srcY+height)` of a keyframe (or a separator band)
    /// placed at `destY` in the output. `segmentLocalY` is the destination Y within its
    /// segment, used by the PDF paginator.
    struct Piece {
        var keyframe: Keyframe?          // nil => separator band
        var srcY: Int
        var height: Int
        var destY: Int
        var segmentLocalY: Int
    }

    struct SegmentLayout {
        var pieces: [Piece]
        var height: Int
    }

    struct Layout {
        var pieces: [Piece]
        var segments: [SegmentLayout]
        var width: Int
        var totalHeight: Int
    }

    private func plan(_ session: StitchSession, refinedSeams: [Seam], images: (Keyframe) throws -> CGImage) throws -> Layout {
        let dyByFrom = Dictionary(uniqueKeysWithValues: refinedSeams.map { ($0.fromIndex, $0.provisionalDy) })
        let chromeTop = refinedSeams.first?.chromeTopPixels ?? 0
        let chromeBottom = refinedSeams.first?.chromeBottomPixels ?? 0
        let segmentsKF = splitIntoSegments(session)

        let width = try firstImage(session, images).width
        var pieces: [Piece] = []
        var segments: [SegmentLayout] = []
        var cursor = 0

        for (s, seg) in segmentsKF.enumerated() {
            if s > 0 {
                pieces.append(Piece(keyframe: nil, srcY: 0, height: separatorHeight, destY: cursor, segmentLocalY: 0))
                cursor += separatorHeight
            }
            var segPieces: [Piece] = []
            var localY = 0
            let h = seg[0].pixelHeight
            let band = max(1, h - chromeTop - chromeBottom)

            func add(_ kf: Keyframe?, _ srcY: Int, _ height: Int) {
                let p = Piece(keyframe: kf, srcY: srcY, height: height, destY: cursor, segmentLocalY: localY)
                pieces.append(p); segPieces.append(p); cursor += height; localY += height
            }

            if seg.count == 1 {
                add(seg[0], 0, h)
            } else {
                add(seg[0], 0, h - chromeBottom)   // top chrome + full content
                for j in 1..<seg.count {
                    let rawDy = dyByFrom[seg[j - 1].index] ?? band
                    let dy = min(max(rawDy, 1), band)
                    add(seg[j], h - chromeBottom - dy, dy)
                }
                if chromeBottom > 0 { add(seg.last!, h - chromeBottom, chromeBottom) }
            }
            segments.append(SegmentLayout(pieces: segPieces, height: localY))
        }

        return Layout(pieces: pieces, segments: segments, width: width, totalHeight: cursor)
    }

    private func splitIntoSegments(_ session: StitchSession) -> [[Keyframe]] {
        let ordered = session.keyframes.sorted { $0.index < $1.index }
        var segments: [[Keyframe]] = []
        var current: [Keyframe] = []
        for kf in ordered {
            current.append(kf)
            if session.hasSegmentBreak(after: kf.index) {
                segments.append(current); current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    // MARK: - Drawing

    /// Draw source rows `[srcRow, srcRow+height)` of `piece` at output row `destY`.
    ///
    /// Uses clip-and-draw rather than `CGImage.cropping` — an unflipped bitmap context
    /// reproduces a drawn CGImage upright, so drawing the whole image offset by
    /// `destY - srcRow` and clipping to the destination band places source rows exactly,
    /// side-stepping `cropping`'s bottom-referenced coordinate system.
    private func drawStrip(_ piece: Piece, srcRow: Int, height: Int, destY: Int, in ctx: CGContext, images: (Keyframe) throws -> CGImage) {
        let clip = CGRect(x: 0, y: destY, width: ctx.width, height: height)
        guard let kf = piece.keyframe else {
            ctx.setFillColor(gray: 0.85, alpha: 1)
            ctx.fill(clip)
            return
        }
        guard let img = try? images(kf) else { return }
        ctx.saveGState()
        ctx.clip(to: clip)
        ctx.draw(img, in: CGRect(x: 0, y: destY - srcRow, width: img.width, height: img.height))
        ctx.restoreGState()
    }

    // MARK: - Refinement

    /// Pixel-exact vertical refinement around the provisional offset; falls back to the
    /// provisional value when the local match isn't confident.
    private func refineVertical(_ a: CGImage, _ b: CGImage, provisional: Int) -> (dy: Int, confident: Bool) {
        let h = a.height
        let pa = profiler.profile(a, forcingHeight: h)
        let pb = profiler.profile(b, forcingHeight: b.height)
        let lo = max(1, provisional - refinementDelta)
        let hi = min(h - matcher.minimumOverlap, provisional + refinementDelta)
        guard hi >= lo else { return (provisional, false) }
        let m = matcher.match(pa, pb, searchRange: lo...hi)
        if m.confidence >= refinementConfidence { return (m.dy, true) }
        return (provisional, false)
    }

    /// Lightweight incidental horizontal shift over the overlap band (monitoring only —
    /// `dx` is never modeled, just flagged). Returns 0 when there's no decisive shift.
    private func measureHorizontal(_ a: CGImage, _ b: CGImage, dy: Int) -> Int {
        let sampleRows = 24
        // Overlap in b's space: b rows [0, h-dy) correspond to a rows [dy, h).
        let bandTop = max(0, (a.height - dy) / 2 - sampleRows / 2)
        guard bandTop + sampleRows <= min(a.height - dy, b.height) else { return 0 }
        // Full width (no downscale) so a few-pixel shift isn't lost to resampling.
        guard let ca = columnMeans(a, y: bandTop + dy, rows: sampleRows, targetWidth: a.width),
              let cb = columnMeans(b, y: bandTop, rows: sampleRows, targetWidth: b.width) else { return 0 }
        var best = 0
        var bestScore = Float.greatestFiniteMagnitude
        var runnerUp = Float.greatestFiniteMagnitude
        let width = min(ca.count, cb.count)
        for shift in -6...6 {
            var sum: Float = 0
            var count: Float = 0
            for x in 0..<width {
                let bx = x + shift
                guard bx >= 0, bx < width else { continue }
                sum += abs(ca[x] - cb[bx]); count += 1
            }
            guard count > 0 else { continue }
            let score = sum / count
            if score < bestScore { runnerUp = bestScore; bestScore = score; best = shift }
            else if score < runnerUp { runnerUp = score }
        }
        // Only report a decisive nonzero shift.
        if best != 0, runnerUp < .greatestFiniteMagnitude, bestScore < runnerUp * 0.7 { return best }
        return 0
    }

    private func columnMeans(_ image: CGImage, y: Int, rows: Int, targetWidth: Int = 64) -> [Float]? {
        let width = min(targetWidth, image.width)
        let cs = CGColorSpaceCreateDeviceGray()
        // cropping is bottom-referenced; convert the genuine-top y.
        let cropY = image.height - y - rows
        guard cropY >= 0, let ctx = CGContext(data: nil, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let crop = image.cropping(to: CGRect(x: 0, y: cropY, width: image.width, height: rows)) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: rows))
        guard let data = ctx.data else { return nil }
        let bpr = ctx.bytesPerRow
        var cols = [Float](repeating: 0, count: width)
        data.withMemoryRebound(to: UInt8.self, capacity: bpr * rows) { base in
            for r in 0..<rows {
                for c in 0..<width { cols[c] += Float(base[r * bpr + c]) }
            }
        }
        return vDSP.divide(cols, Float(rows * 255))
    }

    private func firstImage(_ session: StitchSession, _ images: (Keyframe) throws -> CGImage) throws -> CGImage {
        let first = session.keyframes.min { $0.index < $1.index }!
        return try images(first)
    }
}
