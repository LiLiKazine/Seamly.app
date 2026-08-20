import SwiftUI

/// THE answer to the Paper direction's one real weakness.
///
/// On a light ground a thin rule over white captured content can be missed. So the signal does
/// not live on the image — it lives in the MARGIN, where the ground is always paper and
/// contrast is guaranteed regardless of what was captured. A numbered ring, a proof-reader's
/// mark: legible, countable, tappable, and tied to its row in the queue **by number**.
struct MarginMarker: View {
    let n: Int
    let kind: CaptureMark.Kind
    var selected: Bool = false
    let action: () -> Void

    private var color: Color {
        switch kind {
        case .gap: SeamlyColor.markGap
        case .confident: SeamlyColor.inkFaint
        case .flagged: SeamlyColor.markFlag
        }
    }

    var body: some View {
        Button(action: action) {
            Text("\(n)")
                .font(SeamlyFont.caps)
                .monospacedDigit()
                .foregroundStyle(selected ? SeamlyColor.sheet : color)
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(selected ? color : SeamlyColor.paper)
                }
                .overlay {
                    Circle().strokeBorder(color, lineWidth: 1.5)
                }
                // The ring is 24 pt but the target must not be, and the rail is only 34 pt
                // wide — so the target grows vertically, where there is room.
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .animation(SeamlyMotion.press, value: selected)
        .accessibilityLabel("Mark \(n)")
        .accessibilityIdentifier("margin-marker-\(n)")
    }
}
