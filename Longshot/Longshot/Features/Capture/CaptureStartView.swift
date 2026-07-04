import SwiftUI

/// The Capture call-to-action: the real system broadcast picker plus a one-line reminder of
/// the flow. Shown as the hero on an empty Library and in a menu elsewhere.
struct CaptureStartView: View {
    var showHelp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.15))
                    .frame(width: 96, height: 96)
                BroadcastPickerButton()
                    .frame(width: 80, height: 80)
            }
            Text("Start Capture")
                .font(.headline)
            Text("Pick Longshot, switch to the app you want, and scroll steadily.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("How it works", action: showHelp)
                .font(.footnote)
        }
        .padding()
    }
}
