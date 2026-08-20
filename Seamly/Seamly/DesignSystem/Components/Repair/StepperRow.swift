import SwiftUI

/// The ADVANCED path, never the default. Available behind *Adjust manually* for people who want
/// the number; the queue is what everyone else uses.
///
/// Tabular figures so the row does not reflow as the value steps.
struct StepperRow: View {
    let label: String
    let value: Int
    var unit: String = "px"
    var step: Int = 1
    var range: ClosedRange<Int>
    var hint: String?
    let onChange: (Int) -> Void

    private func set(_ direction: Int) {
        let next = value + direction * step
        onChange(min(max(range.lowerBound, next), range.upperBound))
    }

    var body: some View {
        HStack(spacing: SeamlySpace.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
                if let hint {
                    Text(hint).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
                }
            }
            Spacer(minLength: SeamlySpace.s4)
            Text("\(value) \(unit)")
                .font(SeamlyFont.mono)
                .monospacedDigit()
                .foregroundStyle(SeamlyColor.inkMuted)
                .frame(minWidth: 68, alignment: .trailing)
            HStack(spacing: 0) {
                stepButton("minus", label: "Decrease \(label)") { set(-1) }
                    .disabled(value <= range.lowerBound)
                Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                stepButton("plus", label: "Increase \(label)") { set(1) }
                    .disabled(value >= range.upperBound)
            }
            .frame(height: 34)
            .background(SeamlyColor.paperSunk)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
        }
        .frame(minHeight: SeamlySpace.hitMin)
        .padding(.vertical, SeamlySpace.s3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(SeamlyColor.accent)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
