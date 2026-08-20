import SwiftUI
import StitchKit

/// Compact-width library row. Ruled, not carded — a document lists things on rules.
struct CaptureListRow: View {
    let capture: Capture
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SeamlySpace.s4) {
                CaptureThumbnail(proxy: capture.proxy, marks: capture.displayMarks)
                    .frame(width: 46, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                    Text(SeamlyNumber.dimensions(
                        width: Int(capture.pixelSize.width),
                        height: Int(capture.pixelSize.height)
                    ))
                    .font(SeamlyFont.mono)
                    .monospacedDigit()
                    .foregroundStyle(SeamlyColor.inkFaint)
                    CaptureStatusNotes(capture: capture, size: .small)
                }
                Spacer(minLength: SeamlySpace.s4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .padding(.vertical, SeamlySpace.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-row")
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// The badges a capture wears wherever it is listed. The counts come from `Capture` itself, so
/// this really is one answer to "how many are flagged" rather than a third hand-rolled copy of
/// the filter.
struct CaptureStatusNotes: View {
    let capture: Capture
    var size: StatusNote.Size = .small

    var body: some View {
        let ready = capture.phase == .ready
        let flagged = ready ? capture.flaggedCount : 0
        let gaps = ready ? capture.gapCount : 0
        HStack(spacing: SeamlySpace.s2) {
            if case .failed = capture.phase { StatusNote(kind: .failed, size: size) }
            if capture.phase == .processing { StatusNote(kind: .processing, size: size) }
            if capture.session.status == .recording { StatusNote(kind: .incomplete, size: size) }
            if flagged > 0 { StatusNote(kind: .flagged, count: flagged, size: size) }
            if gaps > 0 { StatusNote(kind: .gap, count: gaps, size: size) }
        }
    }
}
