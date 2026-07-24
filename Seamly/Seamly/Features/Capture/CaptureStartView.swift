import SwiftUI

/// The three ways to make a long screenshot: Record (live broadcast), From Video, From Photos.
struct CaptureStartView: View {
    let model: LibraryModel
    var showHelp: () -> Void
    var onStarted: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.tint.opacity(0.15)).frame(width: 96, height: 96)
                BroadcastPickerButton().frame(width: 80, height: 80)
            }
            Text("Record").font(.headline)
            Text("Pick Seamly, switch to the app you want, and scroll steadily.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Divider().padding(.vertical, 4)

            VideoImportButton(model: model, onStarted: onStarted)
            PhotoImportButton(model: model, onStarted: onStarted)

            Button("How it works", action: showHelp).font(.footnote)
        }
        .padding()
    }
}
