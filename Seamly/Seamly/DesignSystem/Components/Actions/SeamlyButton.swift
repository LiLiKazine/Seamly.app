import SwiftUI

/// PAPER buttons: filled is a solid ink-blue slab, tonal is a wash, plain is bare type. The
/// radius is small — this is a document, not a bubble.
struct SeamlyButton<Label: View>: View {
    enum Variant { case filled, tonal, outline, plain, danger }
    enum Size { case small, medium, large }

    var variant: Variant = .filled
    var size: Size = .medium
    var symbol: String?
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        switch variant {
        case .filled: SeamlyColor.inkInverse
        case .tonal, .plain: SeamlyColor.accent
        case .outline: SeamlyColor.ink
        case .danger: SeamlyColor.markError
        }
    }

    private var background: Color {
        switch variant {
        case .filled: SeamlyColor.accent
        case .tonal: SeamlyColor.accentWash
        case .danger: SeamlyColor.washError
        case .outline, .plain: .clear
        }
    }

    private var height: CGFloat {
        switch size {
        case .small: 36
        case .medium: SeamlySpace.hitMin
        case .large: 52
        }
    }

    private var font: Font {
        size == .small ? SeamlyFont.footnote : SeamlyFont.headline
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: 12
        case .medium: 18
        case .large: 22
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeamlySpace.s3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: size == .small ? 16 : 18))
                }
                label()
                    // Wraps rather than elides. With a fixed height the label was single-line,
                    // so "Review them" became "Review the…" at accessibility sizes — an action
                    // whose own name is cut off.
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .font(font)
            .foregroundStyle(foreground)
            .frame(minWidth: SeamlySpace.hitMin)
            // A MINIMUM height. The padding is free at ordinary sizes — the label is far shorter
            // than the slab, so `minHeight` still decides and the design's 36/44/52 pt slabs are
            // painted exactly — and it is what lets the slab grow around wrapped text instead.
            .padding(.vertical, 4)
            .frame(minHeight: height)
            .padding(.horizontal, horizontalPadding)
            .background(background)
            .overlay {
                if variant == .outline {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.ruleStrong, lineWidth: 1)
                }
            }
            .seamlyCorners(SeamlyRadius.sm)
            .opacity(isEnabled ? 1 : SeamlyMotion.disabledOpacity)
            // The design specifies a 36pt slab for `.small`, and that is what gets painted —
            // but a 36pt tap target is below the 44pt floor. So the target grows around the
            // slab rather than the slab growing to meet it: `minHeight` first, `contentShape`
            // after, so the whole 44pt box is tappable while only 36pt is drawn.
            .frame(minHeight: SeamlySpace.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SeamlyButton where Label == Text {
    init(_ title: String, variant: Variant = .filled, size: Size = .medium,
         symbol: String? = nil, action: @escaping () -> Void) {
        self.init(variant: variant, size: size, symbol: symbol, action: action) { Text(title) }
    }
}
