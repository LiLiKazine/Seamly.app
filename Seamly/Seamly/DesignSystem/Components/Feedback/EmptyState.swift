import SwiftUI

struct EmptyState<Actions: View>: View {
    var symbol: String = "photo"
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: SeamlySpace.s4) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(SeamlyColor.inkFaint)
            Text(title)
                .font(SeamlyFont.title3)
                .foregroundStyle(SeamlyColor.ink)
                .seamlyDisplayTracking()
            if let message {
                Text(message)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    // No ch-to-pt guess: the column caps the measure, per FEASIBILITY.md.
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .frame(maxWidth: SeamlySpace.columnMax)
        .padding(.vertical, SeamlySpace.s10)
        .padding(.horizontal, SeamlySpace.gutterCompact)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String = "photo", title: String, message: String? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
