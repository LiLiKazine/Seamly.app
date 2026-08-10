import SwiftUI

/// Renders a `CaptureCondition` inline. One implementation and one severity scale, so the
/// same underlying state can never read two different ways in two different places — which
/// is exactly what the harness UI did.
///
/// Shows the **primary** observation only. A disclosure reveals the rest; presenting four
/// badges to someone who wanted a screenshot is what made the old UI read as a tool.
///
/// Owns its own insets, so a condition with nothing to say occupies no space at all rather
/// than leaving an empty strip above every clean capture.
struct ConditionNotice: View {
    let condition: CaptureCondition

    @State private var expanded = false

    var body: some View {
        switch condition {
        // `.nothingToStitch` and `.failed` never render inline: `ResultView` gives each of them
        // a whole screen (`NothingToStitchView` / `CaptureFailureView`). They used to have rows
        // here too, which meant a second, differently worded copy of the same user-facing
        // strings inside the one type that exists to keep there being exactly one.
        case .clean, .stitching, .nothingToStitch, .failed:
            EmptyView()
        case .imperfect(let primary, let all):
            imperfect(primary: primary, all: all)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func imperfect(primary: Imperfection, all: [Imperfection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                symbol: symbol(for: primary.kind),
                headline: primary.headline,
                detail: primary.detail,
                severity: primary.severity
            )
            if all.count > 1 {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(all.dropFirst()) { item in
                            row(
                                symbol: symbol(for: item.kind),
                                headline: item.headline,
                                detail: item.detail,
                                severity: item.severity
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("\(all.count - 1) more").font(.caption)
                }
            }
        }
    }

    private func row(symbol: String, headline: String, detail: String, severity: Severity) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(severity == .warning ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(for kind: Imperfection.Kind) -> String {
        switch kind {
        case .endedEarly: "exclamationmark.circle"
        case .gaps: "rectangle.split.1x2"
        case .unresolvedBars: "rectangle.dashed"
        case .flaggedJoins: "arrow.left.and.right"
        case .orderAssumed: "arrow.up.arrow.down"
        }
    }
}

#Preview("Imperfect") {
    ConditionNotice(
        condition: CaptureCondition(
            ready: CaptureFacts(segmentBreaks: 2, flaggedSeams: 1, orderAssumed: true)
        )
    )
}
