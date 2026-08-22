import SwiftUI

/// Return-home IA: the capture affordance is PERMANENTLY present, never a toolbar icon.
/// Docked at the bottom, in thumb reach, with the two import paths flanking it so the hero is
/// unmistakable but the alternatives cost one tap.
///
/// The centre is `BroadcastPickerButton` rather than a `Button`, because
/// `RPSystemBroadcastPickerView` has no SwiftUI equivalent and is the project's one sanctioned
/// UIKit exception. It draws a fixed **black** glyph in both appearances and does not adapt, so
/// the accent slab behind it carries the contrast on its own, exactly as `HomeView`'s disc did.
///
/// Width is capped: a 1024 pt-wide capture button on iPad is absurd.
struct CaptureDock: View {
    var recording: Bool = false
    let onVideo: () -> Void
    let onPhotos: () -> Void

    var body: some View {
        HStack(spacing: SeamlySpace.s4) {
            side(symbol: "film", label: "From a screen recording", action: onVideo)
            ZStack {
                // The picker is at the BOTTOM of the stack at full opacity, and our own slab is
                // painted opaque on top of it. It must NOT be faded to hide it: SwiftUI declines
                // to route touches into a near-transparent `UIViewRepresentable` host, so the
                // `.opacity(0.02)` this used to carry silently ate every tap — UIKit's own
                // `hitTest` still returned the picker's private `UIButton` (0.02 clears UIKit's
                // documented 0.01 alpha floor), so the view looked correct from every angle
                // except the only one that mattered. Occlusion costs nothing: z-order does not
                // affect hit-testing, `allowsHitTesting(false)` on the covers lets the touch
                // fall through, and there is no undocumented threshold left to sit near.
                //
                // Must fill the slab. `RPSystemBroadcastPickerView` reports a small intrinsic
                // size, and a ZStack child without its own flexible frame is laid out at that
                // size and centred — which would leave the hero button tappable only in a
                // circle at its middle, with dead zones either side.
                //
                // We present the picker as-is; reaching into its private subviews to restyle or
                // auto-tap it is the fragility we refuse.
                BroadcastPickerButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(recording ? "Recording" : "Record")
                    .accessibilityIdentifier("record-button")
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .fill(recording ? SeamlyColor.markRec : SeamlyColor.accent)
                    .allowsHitTesting(false)
                HStack(spacing: SeamlySpace.s3) {
                    Image(systemName: "record.circle").font(.system(size: 20, weight: .light))
                    Text(recording ? "Recording" : "Record").font(SeamlyFont.headline)
                }
                .foregroundStyle(SeamlyColor.inkInverse)
                .allowsHitTesting(false)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            side(symbol: "photo.on.rectangle", label: "From screenshots", action: onPhotos)
        }
        .frame(maxWidth: SeamlySpace.columnMax)
        .frame(maxWidth: .infinity)
    }

    private func side(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SeamlyColor.ink)
                .frame(width: 52, height: 52)
                .background(SeamlyColor.paperRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.rule, lineWidth: 1)
                }
                .seamlyCorners(SeamlyRadius.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
