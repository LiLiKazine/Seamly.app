import SwiftUI

/// A capture rendered as a SHEET: white, square-cornered, with its own edge and lift, sitting
/// on the paper ground.
///
/// Never bled to the screen edge — the edge is what tells you where the capture stops and the
/// app begins, which is the job a black canvas does in a dark system.
///
/// The white is `SeamlyColor.sheet`, which is fixed in BOTH themes and is not a semantic
/// background: a capture has its own brightness and must never be dimmed in dark mode.
struct CaptureSheetView<Content: View>: View {
    /// A thin strip down the right edge showing the whole capture squeezed, so length is
    /// legible without a misleading crop. Off inside `CaptureView`, which shows the capture
    /// itself; on for the library, where the crop is top-anchored and short.
    var ribbon: Bool = false
    /// Drawn as ticks on the ribbon, so a library thumbnail still says where its doubt is.
    var ribbonMarks: [CaptureMark] = []
    /// The whole capture, squeezed to fill the ribbon.
    var ribbonImage: CGImage?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Rectangle()
            .fill(SeamlyColor.sheet)
            .overlay {
                HStack(spacing: 0) {
                    content()
                    if ribbon {
                        ZStack(alignment: .topLeading) {
                            if let ribbonImage {
                                Image(decorative: ribbonImage, scale: 1)
                                    .resizable()
                                    .opacity(0.85)
                            } else {
                                SeamlyColor.paperSunk
                            }
                            GeometryReader { geo in
                                ForEach(ribbonMarks.filter { $0.kind != .confident }) { mark in
                                    Rectangle()
                                        .fill(mark.kind == .gap ? SeamlyColor.markGap : SeamlyColor.markFlag)
                                        .frame(height: 2)
                                        .offset(y: geo.size.height * CGFloat(mark.atPct))
                                }
                            }
                        }
                        .frame(width: 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                        }
                    }
                }
            }
            .clipShape(Rectangle())
            .seamlySheetLift()
    }
}
