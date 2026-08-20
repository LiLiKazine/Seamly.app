import SwiftUI
import CoreGraphics

/// A capture as a small plate: white sheet, square corners, a **top-anchored** crop, and the
/// ribbon down its right edge.
///
/// Principle 3: the crop is top-anchored. The middle of a 1:40 image is an unrecognisable slice
/// that reads as "not stitched".
struct CaptureThumbnail: View {
    let proxy: CGImage?
    var marks: [CaptureMark] = []
    var ribbon: Bool = true

    var body: some View {
        CaptureSheetView(ribbon: ribbon, ribbonMarks: marks, ribbonImage: proxy) {
            if let proxy {
                GeometryReader { geo in
                    Image(decorative: proxy, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
            } else {
                SeamlyColor.paperSunk
            }
        }
        // `.clipped()` above only affects painting: without this the hit-test and
        // accessibility frame follow the aspect-filled image's own unclipped render size,
        // which for a capture many screens tall is wildly bigger than the box. This bit
        // HomeView's recents thumbnail — see docs/logs/2026-08-18-02-guided-repair.md.
        .contentShape(Rectangle())
    }
}
