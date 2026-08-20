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
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .fill(recording ? SeamlyColor.markRec : SeamlyColor.accent)
                HStack(spacing: SeamlySpace.s3) {
                    Image(systemName: "record.circle").font(.system(size: 20, weight: .light))
                    Text(recording ? "Recording" : "Record").font(SeamlyFont.headline)
                }
                .foregroundStyle(SeamlyColor.inkInverse)
                .allowsHitTesting(false)
                // The picker sits on top, transparent, and takes the tap. Reaching into its
                // private subviews to restyle or auto-tap it is the fragility we refuse.
                BroadcastPickerButton()
                    .opacity(0.02)
                    .accessibilityLabel(recording ? "Recording" : "Record")
                    .accessibilityIdentifier("record-button")
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
