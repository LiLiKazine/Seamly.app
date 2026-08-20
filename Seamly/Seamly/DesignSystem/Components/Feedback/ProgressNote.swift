import SwiftUI

/// Determinate for reading a video, where a real percentage exists. Indeterminate for
/// stitching, which genuinely has none — the work is data-dependent and finishes when the
/// seams are found. **Never fake progress.**
struct ProgressNote: View {
    let label: String
    /// `nil` means indeterminate, and the copy beside it must say so in words.
    var value: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    var body: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(SeamlyFont.footnote).foregroundStyle(SeamlyColor.ink)
                Spacer()
                if let value {
                    Text("\(Int((value * 100).rounded()))%")
                        .font(SeamlyFont.mono)
                        .foregroundStyle(SeamlyColor.inkMuted)
                }
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(SeamlyColor.paperSunk).frame(height: 3)
                GeometryReader { geo in
                    if let value {
                        Rectangle()
                            .fill(SeamlyColor.accent)
                            .frame(width: geo.size.width * CGFloat(value))
                            .animation(SeamlyMotion.base, value: value)
                    } else if reduceMotion {
                        // No sweep to run, so draw nothing rather than parking a bar at some
                        // arbitrary fill — a still bar at 38% reads as "38% done", which is
                        // the exact lie this component exists to avoid. The label carries it.
                        Color.clear
                    } else {
                        // A genuine SWEEP, not a fill. Stitching has no percentage — the work
                        // is data-dependent and finishes when the seams are found — so the bar
                        // must show activity without implying an amount. `--dur-stitching`
                        // exists in the token set for exactly this.
                        Rectangle()
                            .fill(SeamlyColor.accent)
                            .frame(width: geo.size.width * 0.38)
                            .offset(x: sweeping ? geo.size.width : -geo.size.width * 0.38)
                            .animation(
                                SeamlyMotion.stitching.repeatForever(autoreverses: false),
                                value: sweeping
                            )
                            .onAppear { sweeping = true }
                    }
                }
                .frame(height: 3)
                .clipped()
            }
        }
        .padding(.horizontal, SeamlySpace.s5)
        .padding(.vertical, SeamlySpace.s4)
        .background(SeamlyColor.paperRaised)
        .overlay {
            RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                .strokeBorder(SeamlyColor.rule, lineWidth: 1)
        }
        .seamlyCorners(SeamlyRadius.sm)
    }
}
