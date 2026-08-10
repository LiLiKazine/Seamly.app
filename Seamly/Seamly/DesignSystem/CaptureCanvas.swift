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
        ScrollView([.vertical, .horizontal]) {
            Image(decorative: proxy, scale: 1)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom.scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { zoom.update(magnification: $0.magnification) }
                        .onEnded { _ in withAnimation(.snappy) { zoom.end() } }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) { zoom.reset() }
                }
                .accessibilityLabel("Stitched screenshot")
                .accessibilityHint("Pinch to zoom. Double-tap to fit.")
        }
    }
}
