import SwiftUI

/// A 44 pt target always, even when the glyph is 20. `count` renders a numeral beside the
/// glyph rather than a bare dot — state is never colour alone.
struct IconButton: View {
    let symbol: String
    let label: String
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20))
                if let count, count > 0 {
                    Text("\(count)").font(SeamlyFont.mono)
                }
            }
            .foregroundStyle(SeamlyColor.inkMuted)
            .padding(.horizontal, SeamlySpace.s3)
            .seamlyHitTarget()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
