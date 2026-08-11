import SwiftUI
import CoreGraphics

/// The scrollable, zoomable viewer for a stitched capture.
///
/// Takes a **display proxy**, never a full-resolution composite: a GPU texture tops out around
/// 16,384 px per side and a full-res stitch routinely exceeds that, so binding one to an
/// `Image` fails to render. `StitchAssembler.makeProxy` caps the height at 4096 px.
struct CaptureCanvas: View {
    let proxy: CGImage

    @State private var zoom = ZoomState()

    var body: some View {
        GeometryReader { viewport in
            ScrollView([.vertical, .horizontal]) {
                let size = contentSize(across: viewport.size.width)
                Image(decorative: proxy, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { zoom.update(magnification: $0.magnification) }
                            .onEnded { _ in withAnimation(.snappy) { zoom.end() } }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) { zoom.reset() }
                    }
                    .accessibilityLabel("Stitched screenshot")
                    // The double-tap calls `reset()`, which returns to 1× — the whole image is
                    // still far too tall to be on screen at once, so promising "fit" would be
                    // a lie about what happens.
                    .accessibilityHint("Pinch to zoom. Double-tap to zoom back out.")
            }
        }
    }

    /// The image's **layout** size at the current zoom.
    ///
    /// Zoom has to change the layout size, not just the drawing: `scaleEffect` is a render-time
    /// transform that leaves the view's measured size at 1×, so the scroll view's content
    /// extent never grows and the magnified detail sits outside every reachable scroll offset —
    /// pinch to 3× to inspect a join and the join is unreachable.
    ///
    /// 1× means *fill the width and scroll down*, not shrink a long screenshot until all of it
    /// fits on screen — at that size nothing in it would be legible.
    private func contentSize(across width: CGFloat) -> CGSize {
        let aspect = CGFloat(proxy.height) / CGFloat(max(proxy.width, 1))
        let scaled = width * zoom.scale
        return CGSize(width: scaled, height: scaled * aspect)
    }
}
