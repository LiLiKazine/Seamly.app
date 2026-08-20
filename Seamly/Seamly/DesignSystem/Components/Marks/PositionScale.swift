import SwiftUI

/// Principle 4: position is always answerable. The whole capture squeezed into a ruled scale,
/// with the viewport as a bracket and every mark as a tick.
///
/// **Ruled, not filled** — a document's edge scale rather than a video scrubber. Goes
/// horizontal on a short viewport (landscape iPhone), where a vertical scale would eat the
/// little height there is.
struct PositionScale: View {
    let heightPx: Int
    let viewportTopPct: Double
    let viewportPct: Double
    let marks: [CaptureMark]
    var orientation: Axis = .vertical
    var onScrub: ((Double) -> Void)?

    private func tone(_ kind: CaptureMark.Kind) -> Color {
        switch kind {
        case .flagged: SeamlyColor.markFlag
        case .gap: SeamlyColor.markGap
        case .confident: SeamlyColor.ruleStrong
        }
    }

    var body: some View {
        GeometryReader { geo in
            let along = orientation == .vertical ? geo.size.height : geo.size.width
            ZStack(alignment: .topLeading) {
                // Graduations every 10%, longer every 50% — so it reads as measurement.
                ForEach(0..<11, id: \.self) { i in
                    let length: CGFloat = i % 5 == 0 ? 8 : 4
                    Rectangle()
                        .fill(SeamlyColor.rule)
                        .frame(
                            width: orientation == .vertical ? length : 1,
                            height: orientation == .vertical ? 1 : length
                        )
                        .offset(
                            x: orientation == .vertical ? 0 : along * CGFloat(i) / 10,
                            y: orientation == .vertical ? along * CGFloat(i) / 10 : 0
                        )
                }
                ForEach(marks) { mark in
                    Rectangle()
                        .fill(tone(mark.kind))
                        .frame(
                            width: orientation == .vertical ? nil : 2,
                            height: orientation == .vertical ? 2 : nil
                        )
                        .frame(
                            maxWidth: orientation == .vertical ? .infinity : nil,
                            maxHeight: orientation == .vertical ? nil : .infinity
                        )
                        .offset(
                            x: orientation == .vertical ? 0 : along * CGFloat(mark.atPct),
                            y: orientation == .vertical ? along * CGFloat(mark.atPct) : 0
                        )
                }
                Rectangle()
                    .fill(SeamlyColor.accentWash)
                    .overlay { Rectangle().strokeBorder(SeamlyColor.accent, lineWidth: 1.5) }
                    .frame(
                        width: orientation == .vertical ? nil : max(2, along * CGFloat(viewportPct)),
                        height: orientation == .vertical ? max(2, along * CGFloat(viewportPct)) : nil
                    )
                    .frame(
                        maxWidth: orientation == .vertical ? .infinity : nil,
                        maxHeight: orientation == .vertical ? nil : .infinity
                    )
                    .offset(
                        x: orientation == .vertical ? 0 : along * CGFloat(viewportTopPct),
                        y: orientation == .vertical ? along * CGFloat(viewportTopPct) : 0
                    )
                    .animation(SeamlyMotion.jump, value: viewportTopPct)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(scrub(along: along))
        }
        .frame(
            width: orientation == .vertical ? SeamlySpace.scaleRail : nil,
            height: orientation == .vertical ? nil : SeamlySpace.scaleRail
        )
        .overlay(alignment: orientation == .vertical ? .leading : .top) {
            Rectangle()
                .fill(SeamlyColor.rule)
                .frame(
                    width: orientation == .vertical ? 1 : nil,
                    height: orientation == .vertical ? nil : 1
                )
        }
        .accessibilityElement()
        .accessibilityLabel("Position in capture")
        .accessibilityValue("\(Int((viewportTopPct * 100).rounded())) percent of \(SeamlyNumber.px(heightPx))")
    }

    private func scrub(along: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            guard let onScrub, along > 0 else { return }
            let raw = orientation == .vertical ? value.location.y : value.location.x
            onScrub(Double(min(max(0, raw / along), 1)))
        }
    }
}
