import SwiftUI

/// The only place the buzz can be taught. Nothing may be drawn during a broadcast, so its
/// meaning has to land before the session starts.
struct FirstRunView: View {
    let onDone: () -> Void

    @State private var page = 0

    private struct Step {
        let symbol: String
        let title: String
        let message: String
    }

    private let steps = [
        Step(symbol: "record.circle",
             title: "Tap Record, pick Seamly",
             message: "Seamly records your screen while you scroll another app. Pick Seamly in the sheet and wait for the countdown."),
        Step(symbol: "hand.draw",
             title: "A buzz means slow down",
             message: "Switch to the app you want and scroll at a steady pace. If you feel a buzz you are outrunning the frame rate — ease up, or scroll back a little."),
        Step(symbol: "checkmark.seal",
             title: "Stop and come back",
             message: "Stop from the red indicator, then return. Your capture is waiting, already stitched, with anything uncertain marked."),
    ]

    private var isLast: Bool { page == steps.count - 1 }

    var body: some View {
        VStack(spacing: SeamlySpace.s7) {
            VStack(spacing: SeamlySpace.s7) {
                CueCard(
                    symbol: steps[page].symbol,
                    title: steps[page].title,
                    message: steps[page].message
                )
                if page == 1 {
                    Text("Seamly cannot show you anything while it records — a banner would be captured along with everything else. The buzz is the only signal it can send.")
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            .frame(maxWidth: SeamlySpace.columnMax)

            PageDots(count: steps.count, index: page)

            SeamlyButton(isLast ? "Get Started" : "Next", size: .large) {
                if isLast { onDone() } else { withAnimation(SeamlyMotion.base) { page += 1 } }
            }
            .frame(maxWidth: SeamlySpace.columnMax)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.vertical, SeamlySpace.s7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }
}
