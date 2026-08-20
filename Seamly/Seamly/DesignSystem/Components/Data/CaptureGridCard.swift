import SwiftUI

/// Regular-width library cell. A square grid cell is wrong for a 1:40 image, so every card is a
/// fixed 3:5 window on the START of the capture, uniform whatever the length — length is told
/// by the ribbon and the number, never by cell size.
///
/// The caption sits BELOW the sheet, on paper: a plate with a caption, not text burned over the
/// image.
struct CaptureGridCard: View {
    let capture: Capture
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: SeamlySpace.s3) {
                CaptureThumbnail(proxy: capture.proxy, marks: capture.displayMarks)
                    .aspectRatio(3.0 / 5.0, contentMode: .fit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(capture.title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                    Text(SeamlyNumber.px(Int(capture.pixelSize.height)))
                        .font(SeamlyFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(SeamlyColor.inkFaint)
                    CaptureStatusNotes(capture: capture)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
