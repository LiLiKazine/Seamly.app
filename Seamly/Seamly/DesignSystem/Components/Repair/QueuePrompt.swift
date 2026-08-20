import SwiftUI

/// One question at a time, zoomed to the problem, answerable in a tap. The user never hunts
/// through a 15 000 px image, and never scans a form for the control that matters.
///
/// The affirmative answer is the WIDE, primary one — most flagged seams are actually fine.
///
/// `onNudge` is optional and the chevrons disappear without it. A gap has no lever: the content
/// was never captured, so there is nothing to nudge, and offering a control that does nothing
/// would be worse than offering none. `affirmative` is the word on the primary button, which
/// changes with the kind for the same reason ("Looks right" is a claim a gap cannot make).
struct QueuePrompt<Manual: View>: View {
    let index: Int
    let total: Int
    let kind: Finding.Kind
    let question: String
    var detail: String?
    /// The offset under the finger, shown in mono so it does not reflow as it steps.
    var value: Int?
    var affirmative: String = "Looks right"
    var onNudge: ((Int) -> Void)?
    let onAccept: () -> Void
    let onSkipAll: () -> Void
    @ViewBuilder var manual: () -> Manual

    private var kindWord: String {
        switch kind {
        case .gap: "Gap"
        case .bars: "Bars uncertain"
        case .seam: "Uncertain seam"
        }
    }

    private var kindColor: Color {
        kind == .gap ? SeamlyColor.markGap : SeamlyColor.markFlag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindWord.uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(kindColor)
                Spacer()
                Text("\(index) of \(total)")
                    .font(SeamlyFont.mono)
                    .monospacedDigit()
                    .foregroundStyle(SeamlyColor.inkFaint)
            }

            manual()

            VStack(alignment: .leading, spacing: SeamlySpace.s1) {
                Text(question)
                    .font(SeamlyFont.title3)
                    .foregroundStyle(SeamlyColor.ink)
                    .seamlyDisplayTracking()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: SeamlySpace.s3) {
                if let onNudge {
                    nudge(symbol: "chevron.up", label: "Nudge up") { onNudge(-1) }
                }
                SeamlyButton(affirmative, size: .large, action: onAccept)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("queue-accept")
                if let onNudge {
                    nudge(symbol: "chevron.down", label: "Nudge down") { onNudge(1) }
                }
            }
            // MINIMUM. A fixed height here silently undid `SeamlyButton`'s own `minHeight` +
            // `fixedSize`: at accessibility sizes "No bars here" wraps, the button asks for
            // ~150 pt, and a 52 pt frame centred it straight through the question above and the
            // offset row below. Same class as the eight heights the visual pass converted — this
            // one was a parent overriding a child that had already been fixed.
            .frame(minHeight: 52)

            HStack {
                if let value {
                    // Through `SeamlyNumber`: a real offset runs to four figures, and an
                    // ungrouped reading here beside a grouped one elsewhere is the exact
                    // inconsistency the thin-space rule exists to prevent.
                    Text("dy \(value > 0 ? "+" : "")" + SeamlyNumber.px(value))
                        .font(SeamlyFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(SeamlyColor.inkMuted)
                }
                Spacer()
                Button("Skip all", action: onSkipAll)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.top, SeamlySpace.s5)
        .padding(.bottom, SeamlySpace.s7)
        .frame(maxWidth: .infinity)
        .background(SeamlyColor.paperRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(SeamlyColor.rule).frame(height: 1)
        }
    }

    private func nudge(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SeamlyColor.ink)
                .frame(width: 52)
                .frame(maxHeight: .infinity)
                .background(SeamlyColor.paperSunk)
                .overlay {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.rule, lineWidth: 1)
                }
                .seamlyCorners(SeamlyRadius.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension QueuePrompt where Manual == EmptyView {
    init(index: Int, total: Int, kind: Finding.Kind, question: String, detail: String? = nil,
         value: Int? = nil, affirmative: String = "Looks right",
         onNudge: ((Int) -> Void)? = nil,
         onAccept: @escaping () -> Void, onSkipAll: @escaping () -> Void) {
        self.init(index: index, total: total, kind: kind, question: question, detail: detail,
                  value: value, affirmative: affirmative, onNudge: onNudge,
                  onAccept: onAccept, onSkipAll: onSkipAll) { EmptyView() }
    }
}
