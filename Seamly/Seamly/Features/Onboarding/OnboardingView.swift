import SwiftUI

/// First-run, re-viewable onboarding. Teaches the four-step capture flow, including the
/// mid-capture safety cue as its own step, since the broadcast extension can't draw UI.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Step: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let steps = [
        Step(symbol: "record.circle",
             title: "Tap Record, choose Seamly",
             body: "Seamly records your screen while you scroll another app. Tap Record, pick Seamly in the sheet, and wait for the countdown."),
        Step(symbol: "hand.draw",
             title: "Switch over and scroll steadily",
             body: "Open the app you want and scroll down at a steady, moderate pace."),
        Step(symbol: "iphone.radiowaves.left.and.right",
             title: "One buzz means ease up",
             body: "If you feel a single buzz, you're scrolling too fast to keep everything joined up. Slow down, or scroll back a little and continue."),
        Step(symbol: "checkmark.seal",
             title: "Stop and come back",
             body: "Stop the recording from the red indicator at the top of the screen, then return to Seamly. Your long screenshot will be waiting."),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(spacing: 24) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                        Text(step.title).font(.title2.bold()).multilineTextAlignment(.center)
                        Text(step.body).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page)

            Button(page == steps.count - 1 ? "Get Started" : "Next") {
                if page == steps.count - 1 { dismiss() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}

#Preview { OnboardingView() }
