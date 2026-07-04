import SwiftUI
import StitchKit

/// Non-destructive manual editing, surfaced primarily on flagged seams. Every change edits
/// the manifest and re-composites from the full lossless keyframes — no pixels are discarded.
struct EditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StitchSession
    let model: LibraryModel

    init(session: StitchSession, model: LibraryModel) {
        var seeded = session
        // One editable content band per segment; fill any the extension didn't lock so every
        // segment is adjustable (older manifests default to .unlocked).
        let segmentCount = max(1, seeded.segmentBreaks.count + 1)
        while seeded.contentBands.count < segmentCount { seeded.contentBands.append(.unlocked) }
        _draft = State(initialValue: seeded)
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trim") {
                    stepperRow("Top", value: $draft.topTrim, range: 0...2000, step: 20)
                    stepperRow("Bottom", value: $draft.bottomTrim, range: 0...2000, step: 20)
                }

                if !draft.contentBands.isEmpty {
                    Section("Chrome (crop repeated bars)") {
                        ForEach(draft.contentBands.indices, id: \.self) { i in
                            if draft.contentBands.count > 1 {
                                Text("Segment \(i + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            stepperRow("Top bar", value: bandTop(i), range: 0...600, step: 5)
                            stepperRow("Bottom bar", value: bandBottom(i), range: 0...600, step: 5)
                        }
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

    // Editing a band is an explicit user choice, so clear the low-confidence flag (no more
    // "detection uncertain" warning) as the value is adjusted.
    private func bandTop(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.contentBands[i].topChrome },
                set: { draft.contentBands[i].topChrome = $0; draft.contentBands[i].isLowConfidence = false })
    }
    private func bandBottom(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.contentBands[i].bottomChrome },
                set: { draft.contentBands[i].bottomChrome = $0; draft.contentBands[i].isLowConfidence = false })
    }
    private func offset(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.seams[i].provisionalDy }, set: { draft.seams[i].provisionalDy = $0 })
    }
}
