import SwiftUI

/// Shown while a capture is being read and stitched.
///
/// Video *decode* reports real progress, so it gets a determinate bar. Stitching does not —
/// `StitchAssembler.composite` has no progress callback — and inventing a bar for it would
/// be a lie about how far along the work is.
struct ProcessingView: View {
    /// 0…1 while a video decodes; `nil` while stitching.
    let progress: Double?

    var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress) { Text("Reading video…") }
                    .frame(maxWidth: 260)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Putting it together…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The capture contained no scrolling. This is not an error — the user simply did not scroll
/// the app they recorded — so it reads as coaching, not failure.
struct NothingToStitchView: View {
    var onRecordAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nothing to stitch", systemImage: "arrow.up.and.down")
        } description: {
            Text("This recording didn't scroll, so there was nothing to join together. Start the recording, switch to the app you want, then scroll down steadily.")
        } actions: {
            Button("Record again", action: onRecordAgain)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// The stitch genuinely failed. Shows the real underlying message — never a generic one.
struct CaptureFailureView: View {
    let message: String
    var onRecordAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't finish this one", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Record again", action: onRecordAgain)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Stitching") { ProcessingView(progress: nil) }
#Preview("Decoding") { ProcessingView(progress: 0.42) }
#Preview("Nothing to stitch") { NothingToStitchView(onRecordAgain: {}) }
#Preview("Failed") { CaptureFailureView(message: "The saved frames could not be read.", onRecordAgain: {}) }
