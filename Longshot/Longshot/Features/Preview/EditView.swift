import SwiftUI
import StitchKit

/// Non-destructive manual editing, surfaced primarily on flagged seams. Every change edits
/// the manifest and re-composites from the full lossless keyframes — no pixels are discarded.
struct EditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StitchSession
    let model: LibraryModel

    init(session: StitchSession, model: LibraryModel) {
        _draft = State(initialValue: session)
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trim") {
                    stepperRow("Top", value: $draft.topTrim, range: 0...2000, step: 20)
                    stepperRow("Bottom", value: $draft.bottomTrim, range: 0...2000, step: 20)
                }

                if let first = draft.seams.indices.first {
                    Section("Chrome (crop repeated bars)") {
                        stepperRow("Top bar", value: chromeTop(first), range: 0...600, step: 5)
                        stepperRow("Bottom bar", value: chromeBottom(first), range: 0...600, step: 5)
                    }
                }

                let flagged = draft.seams.indices.filter { draft.seams[$0].isLowConfidence }
                if !flagged.isEmpty {
                    Section("Flagged seams") {
                        ForEach(flagged, id: \.self) { i in
                            VStack(alignment: .leading) {
                                Text("Seam after frame \(draft.seams[i].fromIndex)").font(.subheadline)
                                stepperRow("Offset", value: offset(i), range: 0...4000, step: 1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let edited = draft
                        Task { await model.update(edited); dismiss() }
                    }
                }
            }
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue) px").foregroundStyle(.secondary) }
        }
    }

    private func chromeTop(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.seams[i].chromeTopPixels }, set: { draft.seams[i].chromeTopPixels = $0 })
    }
    private func chromeBottom(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.seams[i].chromeBottomPixels }, set: { draft.seams[i].chromeBottomPixels = $0 })
    }
    private func offset(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.seams[i].provisionalDy }, set: { draft.seams[i].provisionalDy = $0 })
    }
}
