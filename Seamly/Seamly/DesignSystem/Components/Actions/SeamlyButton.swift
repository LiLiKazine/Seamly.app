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
            }
            .font(font)
            .foregroundStyle(foreground)
            .frame(minWidth: SeamlySpace.hitMin)
            .frame(height: height)
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
