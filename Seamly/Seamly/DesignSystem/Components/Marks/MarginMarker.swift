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
                // The ONE place a size is capped, and deliberately: this is a proof-reader's
                // mark, not copy. The rail it lives in is a fixed 34 pt, so a growing digit
                // does not enlarge the ring — it bursts it, and at AX5 the ring rendered as a
                // clipped crescent. Nothing is lost by holding it: the number is decoration for
                // the accessibility label ("Mark 1") that VoiceOver actually reads, and the tap
                // target is already well past 44 pt via the `contentShape` below.
                .dynamicTypeSize(...DynamicTypeSize.large)
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
