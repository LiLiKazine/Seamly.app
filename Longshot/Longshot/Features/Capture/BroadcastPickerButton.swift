import SwiftUI
import ReplayKit

/// SwiftUI wrapper over the system broadcast picker. We present it as-is (no reaching into
/// private subviews to auto-tap — that's fragile across iOS versions) and bias it toward our
/// extension with `preferredExtension`.
struct BroadcastPickerButton: UIViewRepresentable {
    /// Bundle identifier of the LongshotBroadcast upload extension.
    static let extensionBundleID = "io.github.lilikazine.Longshot.Broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        picker.preferredExtension = Self.extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
