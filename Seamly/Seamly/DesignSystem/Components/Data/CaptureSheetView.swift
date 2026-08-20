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
    /// itself; on for the library's thumbnails.
    var ribbon: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Rectangle()
            .fill(SeamlyColor.sheet)
            .overlay { content() }
            .clipShape(Rectangle())
            .seamlySheetLift()
    }
}
