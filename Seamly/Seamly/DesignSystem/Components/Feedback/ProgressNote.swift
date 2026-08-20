import SwiftUI

/// Determinate for reading a video, where a real percentage exists. Indeterminate for
/// stitching, which genuinely has none — the work is data-dependent and finishes when the
/// seams are found. **Never fake progress.**
struct ProgressNote: View {
    let label: String
    /// `nil` means indeterminate, and the copy beside it must say so in words.
    var value: Double?

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
                    Rectangle()
                        .fill(SeamlyColor.accent)
                        .frame(width: geo.size.width * CGFloat(value ?? 0.38))
                        .animation(SeamlyMotion.base, value: value)
                }
                .frame(height: 3)
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
