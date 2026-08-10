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
        seeded.ensureChromeRecordsForKeyframes()
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

                if !draft.keyframes.isEmpty {
                    Section("Chrome (per frame)") {
                        ForEach(draft.keyframes.indices, id: \.self) { i in
                            let keyframe = draft.keyframes[i]
                            if draft.keyframes.count > 1 {
                                Text("Frame \(keyframe.index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            if !draft.chromeEdgesNeedingReview(for: keyframe).isEmpty {
                                Label("One or more bars could not be measured safely — set them manually.", systemImage: "rectangle.dashed")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            chromeEdgeRow("Top bar", edge: .top, keyframe: keyframe)
                            chromeEdgeRow("Bottom bar", edge: .bottom, keyframe: keyframe)
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

    @ViewBuilder
    private func chromeEdgeRow(_ title: String, edge: ChromeEdge, keyframe: Keyframe) -> some View {
        stepperRow(
            title,
            value: chromeValue(edge, keyframe: keyframe),
            range: 0...min(2000, max(0, keyframe.pixelHeight / 2)),
            step: 5
        )
        if hasOverride(edge, keyframeID: keyframe.id) {
            Button("Remove manual \(edge.rawValue) crop") {
                clearOverride(edge, keyframeID: keyframe.id)
            }
            .font(.caption)
        }
    }

    private func chromeValue(_ edge: ChromeEdge, keyframe: Keyframe) -> Binding<Int> {
        Binding(
            get: { rawChromeValue(edge, keyframeID: keyframe.id) },
            set: { setOverride(edge, value: $0, keyframe: keyframe) }
        )
    }

    private func rawChromeValue(_ edge: ChromeEdge, keyframeID: UUID) -> Int {
        draft.chromeValueForEditing(edge, keyframeID: keyframeID)
    }

    private func setOverride(_ edge: ChromeEdge, value: Int, keyframe: Keyframe) {
        draft.setChromeOverride(value, for: edge, keyframeID: keyframe.id)
    }

    private func hasOverride(_ edge: ChromeEdge, keyframeID: UUID) -> Bool {
        draft.hasChromeOverride(edge, keyframeID: keyframeID)
    }

    private func clearOverride(_ edge: ChromeEdge, keyframeID: UUID) {
        draft.setChromeOverride(nil, for: edge, keyframeID: keyframeID)
    }
    private func offset(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.seams[i].provisionalDy }, set: { draft.seams[i].provisionalDy = $0 })
    }
}
