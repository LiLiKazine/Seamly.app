import SwiftUI

/// The Paper nav bar. A custom view rather than the system bar, because the design's bar
/// carries a mono tabular subtitle, a `large` variant, and a paper ground with a rule — none
/// of which a `UINavigationBar` expresses.
///
/// **Cost, accepted:** the screens using this hide the system bar, which disables the
/// interactive swipe-back gesture. Only two pushes exist (Home → Library → Review) and both
/// carry a visible back control. Recorded in the spec as a decision, not discovered later.
struct NavBar<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var large: Bool = false
    var backLabel: String = ""
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: large ? .bottom : .center, spacing: SeamlySpace.s4) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 20))
                        if !backLabel.isEmpty { Text(backLabel).font(SeamlyFont.body) }
                    }
                    .foregroundStyle(SeamlyColor.accent)
                    // BOTH dimensions: `backLabel` is empty on most screens, leaving a bare
                    // 20pt chevron whose intrinsic width is far under the 44pt floor. A height
                    // floor alone would have left it tall and thin.
                    .frame(minWidth: SeamlySpace.hitMin, minHeight: SeamlySpace.hitMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // `backLabel` is empty on every compact screen, which leaves a bare SF Symbol
                // and nothing for VoiceOver to say. The design kit has the same gap because it
                // is a web mock — supplying the spoken name is the port's job, not the mock's.
                .accessibilityLabel(backLabel.isEmpty ? "Back" : backLabel)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(large ? SeamlyFont.largeTitle : SeamlyFont.headline)
                    .foregroundStyle(SeamlyColor.ink)
                    .modifier(TitleTracking(large: large))
                if let subtitle {
                    Text(subtitle)
                        .font(SeamlyFont.mono)
                        .foregroundStyle(SeamlyColor.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) { trailing() }
        }
        .padding(.horizontal, large ? SeamlySpace.gutterCompact : SeamlySpace.s4)
        .padding(.bottom, SeamlySpace.s4)
        .frame(maxWidth: .infinity)
        .background(SeamlyColor.paper)
        .overlay(alignment: .bottom) {
            if !large {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
        }
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, large: Bool = false,
         backLabel: String = "", onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, large: large,
                  backLabel: backLabel, onBack: onBack) { EmptyView() }
    }
}

/// Tracking is absolute points and does not scale with Dynamic Type, so it is applied only at
/// display sizes — never to the subtitle or to body copy. See FEASIBILITY.md.
///
/// The CSS has `--tracking-title: -0.012em` for the compact title, and `em` scales with the
/// type. SwiftUI's `.tracking()` does not, so porting that number would be right at one size
/// and wrong at every other — worse the larger the user sets their type. The compact title is
/// `SeamlyFont.headline`, which grows with Dynamic Type, so it gets no tracking at all. Only
/// the `large` variant, a capped display size, keeps it.
private struct TitleTracking: ViewModifier {
    let large: Bool
    func body(content: Content) -> some View {
        large ? AnyView(content.seamlyDisplayTracking()) : AnyView(content)
    }
}
