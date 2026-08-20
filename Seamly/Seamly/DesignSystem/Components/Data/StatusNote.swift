import SwiftUI

/// State is NEVER colour alone: every note carries its word. A wash behind ink — no coloured
/// left-border card, no bare dot.
struct StatusNote: View {
    enum Kind { case ready, processing, flagged, gap, bars, incomplete, orderAssumed, failed }
    enum Size { case small, medium }

    let kind: Kind
    var count: Int?
    /// Overrides the default word entirely, for the one-off lines the screens need.
    var label: String?
    var size: Size = .medium

    private var word: String {
        switch kind {
        case .ready: "Ready"
        case .processing: "Stitching…"
        case .flagged: "flagged"
        case .gap: "gap"
        case .bars: "bars uncertain"
        case .incomplete: "Incomplete"
        case .orderAssumed: "Order assumed"
        case .failed: "Couldn't stitch"
        }
    }

    private var symbol: String {
        switch kind {
        case .ready: "checkmark"
        case .processing: "list.bullet"
        case .flagged: "flag"
        case .gap: "scissors"
        case .bars: "rectangle.dashed"
        case .incomplete: "exclamationmark.circle"
        case .orderAssumed: "arrow.up.arrow.down"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tone: Color? {
        switch kind {
        case .ready: SeamlyColor.markOK
        case .flagged, .bars: SeamlyColor.markFlag
        case .gap: SeamlyColor.markGap
        case .incomplete, .failed: SeamlyColor.markError
        case .processing, .orderAssumed: nil
        }
    }

    private var wash: Color {
        switch kind {
        case .ready: SeamlyColor.washOK
        case .flagged, .bars: SeamlyColor.washFlag
        case .gap: SeamlyColor.washGap
        case .incomplete, .failed: SeamlyColor.washError
        case .processing, .orderAssumed: .clear
        }
    }

    private var text: String {
        if let label { return label }
        if let count { return "\(count) \(word)" }
        return word
    }

    var body: some View {
        let small = size == .small
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: small ? 11 : 13, weight: .medium))
            Text(text).monospacedDigit()
        }
        .font(small ? SeamlyFont.caps : SeamlyFont.caption)
        .foregroundStyle(tone ?? SeamlyColor.inkMuted)
        .padding(.horizontal, small ? 7 : 9)
        // A MINIMUM height, not a fixed one. Fixed, the chip could not grow with Dynamic Type,
        // so at accessibility sizes its own word was elided — "1 fla…" — and a note whose entire
        // job is to carry the word in text rather than in colour had nothing left to carry it
        // with. The padding keeps it at exactly 20/24 pt at default sizes.
        .padding(.vertical, small ? 3 : 4)
        .frame(minHeight: small ? 20 : 24)
        .fixedSize(horizontal: false, vertical: true)
        .background(wash)
        .seamlyCorners(SeamlyRadius.xs)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
