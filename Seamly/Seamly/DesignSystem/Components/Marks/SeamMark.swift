import SwiftUI

/// How a join is drawn ON the sheet. Deliberately quiet: principle 1 says a good capture must
/// look like ONE IMAGE, so a confident join is nearly invisible and a flagged one is a thin
/// ruled line — not a glowing bar.
///
/// Findability is **not** this component's job. That belongs to `MarginMarker` and
/// `PositionScale`, which sit off the image where the ground is always paper and contrast is
/// guaranteed whatever was captured. That division is the whole reason a light ground works.
struct SeamMark: View {
    let kind: CaptureMark.Kind
    /// Required for a gap — always label what was lost.
    var lostLabel: String?

    private var color: Color {
        switch kind {
        case .confident: SeamlyColor.seamConfident
        case .flagged: SeamlyColor.seamFlag
        case .gap: SeamlyColor.seamGap
        }
    }

    private var width: CGFloat {
        kind == .confident ? SeamlySpace.seamWidth : SeamlySpace.seamWidthMark
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if kind == .gap {
                // Dashed, because nothing joins here — the two sides are not continuous.
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: width, dash: [5, 4]))
                    .foregroundStyle(color)
                    .frame(height: width)
            } else {
                Rectangle().fill(color).frame(height: width)
            }
            if let lostLabel {
                Text(lostLabel)
                    .font(SeamlyFont.mono)
                    .foregroundStyle(SeamlyColor.markGap)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(SeamlyColor.sheet)
                    .padding(.trailing, SeamlySpace.s3)
                    .offset(y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
