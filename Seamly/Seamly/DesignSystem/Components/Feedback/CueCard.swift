import SwiftUI

/// The app's UI during a broadcast is a VIBRATION — nothing may be drawn on screen or it lands
/// in the capture. So the meaning of the buzz has to be taught before the session and explained
/// after it. This component is the only place that happens, which is why it exists at all.
struct CueCard: View {
    enum When { case before, after }

    var symbol: String = "hand.draw"
    var when: When = .before
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: SeamlySpace.s5) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SeamlyColor.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text((when == .before ? "Before you start" : "What that buzz meant").uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(SeamlyColor.inkFaint)
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                Text(message)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SeamlySpace.s5)
        .background(SeamlyColor.paperRaised)
        .overlay {
            RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                .strokeBorder(SeamlyColor.rule, lineWidth: 1)
        }
        .seamlyCorners(SeamlyRadius.sm)
    }
}
