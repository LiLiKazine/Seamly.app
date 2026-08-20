import SwiftUI

/// A listed alternative source, or a listed export destination. Ruled, not carded — a document
/// lists things on rules.
struct ImportRow: View {
    let symbol: String
    let title: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeamlySpace.s4) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(SeamlyColor.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
                    if let detail {
                        Text(detail).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
                    }
                }
                Spacer(minLength: SeamlySpace.s4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .frame(minHeight: 56)
            .padding(.vertical, SeamlySpace.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
    }
}
