import SwiftUI

/// First-run, re-viewable onboarding. Teaches the three-step capture flow — and, crucially,
/// the meaning of the mid-capture safety cue, since the broadcast extension can't draw UI.
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
             title: "Tap Capture, choose Longshot",
             body: "Longshot records your screen while you scroll another app. Tap Capture, pick Longshot in the sheet, and wait for the countdown."),
        Step(symbol: "hand.draw",
             title: "Switch over and scroll steadily",
             body: "Open the app you want to capture and scroll down at a steady, moderate pace. If you feel a buzz, ease up or scroll back a little — you're going too fast."),
        Step(symbol: "checkmark.seal",
             title: "Stop and come back",
             body: "Stop the recording from the red status indicator, then return to Longshot. Your long screenshot will be waiting in the Library."),
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
