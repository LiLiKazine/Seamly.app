import SwiftUI
import ReplayKit
import os

/// SwiftUI wrapper over the system broadcast picker. We present it as-is (no reaching into
/// private subviews to auto-tap — that's fragile across iOS versions) and bias it toward our
/// extension with `preferredExtension`.
///
/// **Never fade this view to hide it.** SwiftUI declines to route touches into a
/// near-transparent `UIViewRepresentable` host, and it does so well above UIKit's documented
/// 0.01 alpha floor for `hitTest`. A `.opacity(0.02)` on the call site shipped a Record button
/// that swallowed every tap while still reporting `isHittable == true` to XCUITest and still
/// returning the picker's private `UIButton` from `window.hitTest` — invisible to the UI tests
/// and to inspection alike. Cover it with opaque content instead; see `CaptureDock`.
struct BroadcastPickerButton: UIViewRepresentable {
    /// Bundle identifier of the SeamlyBroadcast upload extension.
    static let extensionBundleID = "io.github.lilikazine.Seamly.Broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        picker.preferredExtension = Self.extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        #if DEBUG
        OpacityGuard.check(uiView)
        #endif
    }
}

#if DEBUG
/// Catches the one mistake that makes this control silently inert.
///
/// The bug it guards against is invisible to every ordinary check — the view is present, its
/// frame is right, `hitTest` finds the button and XCUITest calls it hittable — so it cannot be
/// covered by a UI test. It can only be caught by looking at the rendered alpha, which is what
/// this does, once, on the next runloop turn after the view has been placed.
private enum OpacityGuard {
    private static let log = Logger(subsystem: "io.github.lilikazine.Seamly", category: "capture")
    private static var checked = false

    /// SwiftUI's routing cuts out somewhere between 0.02 (confirmed dead) and 1.0 (confirmed
    /// live). The exact threshold is undocumented, so this refuses anything meaningfully faded
    /// rather than trying to sit just above a cliff whose position Apple can move.
    private static let floor: CGFloat = 0.95

    static func check(_ picker: RPSystemBroadcastPickerView) {
        guard !checked else { return }
        checked = true
        DispatchQueue.main.async {
            guard picker.window != nil else { checked = false; return }
            // Only the picker and its representable host. A `.opacity()` written on
            // `BroadcastPickerButton` lands on exactly these two, whereas anything higher is a
            // container UIKit may legitimately animate mid-transition — checking those would
            // trip on a push rather than on the mistake.
            let candidates = [picker, picker.superview].compactMap { $0 }
            guard let faded = candidates.first(where: { $0.alpha < floor }) else { return }
            let offender = String(describing: type(of: faded))
            log.error("Broadcast picker is faded (\(offender) alpha=\(faded.alpha)) — SwiftUI will not deliver touches to it and Record will do nothing.")
            assertionFailure(
                "BroadcastPickerButton is rendered at alpha \(faded.alpha) by \(offender). "
                + "SwiftUI will not route touches into a faded UIViewRepresentable, so Record "
                + "will silently do nothing. Cover the picker with opaque content instead of "
                + "fading it — see CaptureDock."
            )
        }
    }
}
#endif
