import SwiftUI
import CoreGraphics

/// A request to pan the capture so a mark is on screen. A token rather than just a position,
/// so asking for the same mark twice fires twice — a user tapping the marker they are already
/// looking at expects it to re-centre, not to do nothing.
struct CaptureJump: Equatable {
    let atPct: Double
    var fraction: CGFloat = 0.4
    let token: Int
}

/// What the sheet is showing.
enum CaptureSheetContent {
    /// The whole capture, downscaled. `StitchAssembler.makeProxy` caps it at 4096 px tall.
    case proxy(CGImage)
    /// The two full-resolution frames either side of one join, live under the finger.
    ///
    /// The proxy is only rebuilt after a commit, so a repair drag against it would move
    /// nothing visible. Filled in by Task 11.
    case join(upper: CGImage, lower: CGImage, alignment: JoinAlignment)
}

/// The sheet, its margin rail and its position scale — shared by Home, Review and the repair
/// queue, so all three agree about where a mark is.
///
/// **This is where the direction lives or dies.** A mark's position on screen is
/// `atPct * contentHeight - scrollY`, and the margin marker beside it must use the same number
/// or the margin stops carrying signal. So there is exactly one `GeometryReader`, exactly one
/// `scrollY`, and every element — the image, the rules on the sheet, the numbered markers, the
/// scale's bracket — is placed from them. There is nothing for them to drift relative to.
///
/// The scroll content is a bare `Color.clear` spacer, which carries no raster: a capture at 6×
/// is tens of thousands of points tall, and a texture that size exceeds the ~16 384 px GPU
/// ceiling. The image is drawn in an overlay pinned to the viewport and offset by `-scrollY`,
/// so nothing larger than the screen is ever rasterised. (`CaptureCanvas`, which this replaces,
/// did bind the whole proxy into the scroll content and had exactly that bug.)
struct CaptureView: View {
    let content: CaptureSheetContent
    /// The whole capture in source pixels — `Placement.totalHeight` and the keyframe width.
    let captureSize: CGSize
    /// Every join, drawn as a quiet rule ON the sheet. Confident ones included and unnumbered.
    var marks: [CaptureMark] = []
    /// Every doubt, drawn as a numbered ring IN the margin.
    ///
    /// Deliberately a separate collection from `marks`, because the two are not the same set.
    /// A confident join is a mark with no finding; a bars finding is a finding with no mark —
    /// it is about a whole frame rather than a join, so there is no line to draw on the sheet,
    /// but it must still be numbered and reachable in the margin. Driving the rail from `marks`
    /// would make every bars finding invisible and unanswerable.
    var findings: [Finding] = []
    var zoom: CGFloat = 1
    var selected: Int?
    var showScale: Bool = true
    var jump: CaptureJump?
    var onSelect: ((Int) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    @State private var scrollY: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    var body: some View {
        VStack(spacing: SeamlySpace.s3) {
            HStack(spacing: SeamlySpace.s3) {
                GeometryReader { geo in
                    let sheetWidth = geo.size.width - SeamlySpace.marginRail - SeamlySpace.s3
                        - (showScale && !layout.isShort ? SeamlySpace.scaleRail + SeamlySpace.s3 : 0)
                    let g = CaptureGeometry(
                        sheetWidth: max(0, sheetWidth),
                        viewportHeight: geo.size.height,
                        captureSize: captureSize,
                        zoom: zoom,
                        scrollY: scrollY
                    )
                    HStack(spacing: SeamlySpace.s3) {
                        marginRail(g)
                        sheet(g)
                        if showScale && !layout.isShort { scale(g) }
                    }
                    .onChange(of: jump) { _, target in
                        guard let target else { return }
                        withAnimation(SeamlyMotion.jump) {
                            scrollPosition.scrollTo(y: g.scrollY(toShow: target.atPct, at: target.fraction))
                        }
                    }
                }
            }
            if showScale && layout.isShort { shortScale() }
        }
    }

    // MARK: - The margin — always paper, so contrast never depends on the capture

    @ViewBuilder
    private func marginRail(_ g: CaptureGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(findings) { finding in
                let y = g.y(atPct: finding.atPct)
                if g.isVisible(y) {
                    MarginMarker(
                        n: finding.n,
                        // A gap reads in its own tone; bars and seams are both "uncertain".
                        kind: finding.kind == .gap ? .gap : .flagged,
                        selected: selected == finding.n,
                        action: { onSelect?(finding.n) }
                    )
                    .offset(y: y - 12)
                }
            }
        }
        .frame(width: SeamlySpace.marginRail)
        .clipped()
    }

    // MARK: - The sheet

    @ViewBuilder
    private func sheet(_ g: CaptureGeometry) -> some View {
        CaptureSheetView {
            switch content {
            case .proxy(let image):
                proxySheet(image, g)
            case .join(let upper, let lower, let alignment):
                joinSheet(upper: upper, lower: lower, alignment: alignment, g: g)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func proxySheet(_ image: CGImage, _ g: CaptureGeometry) -> some View {
        ScrollView(.vertical) {
            // No raster: the extent exists so the scroll view has somewhere to go.
            Color.clear.frame(height: g.contentHeight)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            scrollY = y
        }
        // `alignment: .topLeading` is load-bearing, not decorative. `Image` below carries an
        // explicit `.frame(height: g.contentHeight)` that is routinely taller than this
        // ScrollView's own viewport, so the overlay's *content* is that tall too. The default
        // overlay alignment is `.center`, which would centre that oversized content on the
        // viewport instead of pinning its top edge to it — shifting every mark and the image
        // itself by a hidden, zoom-and-scroll-dependent amount, and silently clipping the
        // margin's numbered rings away from whatever the sheet happens to show. `.topLeading`
        // is what makes `-scrollY` on the image below actually mean "the top of the content is
        // `scrollY` above the viewport's top edge" rather than something else.
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: g.sheetWidth * zoom, height: g.contentHeight)
                    // Centred horizontally: there is deliberately no panning, so whichever
                    // slice is shown at zoom is the middle one, not the left edge.
                    .offset(x: -(g.sheetWidth * zoom - g.sheetWidth) / 2, y: -scrollY)
                ForEach(marks) { mark in
                    let y = g.y(atPct: mark.atPct)
                    if g.isVisible(y) {
                        SeamMark(kind: mark.kind, lostLabel: mark.lostLabel)
                            .offset(y: y)
                    }
                }
            }
            // The overlay must not eat the scroll gesture underneath it.
            .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityLabel("Stitched capture")
        .accessibilityHint("Scroll to move through the capture. Pinch to zoom in.")
        .accessibilityIdentifier("capture-sheet")
    }

    // Filled in by Task 11, when the repair queue needs a live pair under the finger.
    @ViewBuilder
    private func joinSheet(upper: CGImage, lower: CGImage, alignment: JoinAlignment, g: CaptureGeometry) -> some View {
        Color.clear
    }

    // MARK: - The scale

    @ViewBuilder
    private func scale(_ g: CaptureGeometry) -> some View {
        PositionScale(
            heightPx: Int(captureSize.height),
            viewportTopPct: g.viewportTopPct,
            viewportPct: g.viewportPct,
            marks: marks,
            orientation: .vertical,
            onScrub: { pct in
                withAnimation(SeamlyMotion.jump) {
                    scrollPosition.scrollTo(y: g.scrollY(toShow: pct, at: 0.1))
                }
            }
        )
    }

    /// A short viewport (landscape iPhone) gets a horizontal scale below the sheet, because a
    /// vertical one would eat the little height there is.
    @ViewBuilder
    private func shortScale() -> some View {
        PositionScale(
            heightPx: Int(captureSize.height),
            viewportTopPct: 0,
            viewportPct: 1,
            marks: marks,
            orientation: .horizontal,
            onScrub: nil
        )
    }
}

#Preview("Marks line up with the margin") {
    // A tall striped proxy with marks at exact tenths, so a marker sitting off its rule is
    // visible by eye rather than only under a ruler.
    let width = 300, height = 6000
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // A CGBitmapContext has a BOTTOM-left origin, so a bar filled at `pct * height` renders
    // at `1 - pct` from the top once `Image(decorative:)` draws it top-down. Flip the context
    // so the fixture shares the orientation of the thing it is testing. This repo has shipped
    // the un-flipped version of this mistake before: an upside-down synthetic fixture cancelled
    // out a real sign error in VerticalProfile and hid it for three fix cycles (CLAUDE.md,
    // "A green suite here has lied three times"). `TestImages.make` in StitchKit flips for the
    // same reason.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(gray: 0.72, alpha: 1)
    for band in stride(from: 0, to: height, by: 60) {
        ctx.fill(CGRect(x: 0, y: band, width: width, height: 22))
    }
    // A black bar exactly at each mark, so the rule and the marker have something to agree with.
    // Deliberately ASYMMETRIC. A symmetric set (0.2/0.5/0.8) is mirror-invariant, so every ring
    // would land on *a* bar even if the fixture and the geometry were both flipped — the preview
    // could not tell "correct" from "two errors cancelling".
    ctx.setFillColor(gray: 0.1, alpha: 1)
    for pct in [0.15, 0.5, 0.72] {
        ctx.fill(CGRect(x: 0, y: Int(Double(height) * pct), width: width, height: 3))
    }
    let image = ctx.makeImage()!

    return CaptureView(
        content: .proxy(image),
        captureSize: CGSize(width: width, height: height),
        marks: [
            CaptureMark(id: "a", kind: .flagged, atPct: 0.15, n: 1, lostLabel: nil),
            CaptureMark(id: "b", kind: .gap, atPct: 0.5, n: 2, lostLabel: "lost lock"),
            CaptureMark(id: "c", kind: .confident, atPct: 0.72, n: nil, lostLabel: nil),
        ],
        findings: [
            Finding(id: "a", n: 1, kind: .seam, atPct: 0.15, target: .join(0),
                    title: "Seam after frame 1", question: "Does this line up?",
                    detail: "", dy: 100, confidence: 0.3),
            Finding(id: "b", n: 2, kind: .gap, atPct: 0.5, target: .gap(afterKeyframeIndex: 1),
                    title: "Gap after frame 2", question: "Nothing was captured here",
                    detail: "", dy: nil, confidence: nil),
        ],
        selected: 1,
        onSelect: { _ in }
    )
    .padding(SeamlySpace.gutterCompact)
    .background(SeamlyColor.paper)
}
