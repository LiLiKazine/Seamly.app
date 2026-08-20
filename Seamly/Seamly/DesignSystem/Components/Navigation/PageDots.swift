import SwiftUI

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? SeamlyColor.accent : SeamlyColor.ruleStrong)
                    .frame(width: i == index ? 18 : 6, height: 6)
                    .animation(SeamlyMotion.base, value: index)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}
