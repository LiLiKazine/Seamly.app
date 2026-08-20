import SwiftUI

/// Paper sheets slide up as paper: a square top edge with a rule, not a big rounded glass card.
/// The radius stays small so it reads as a sheet, not a bubble.
struct SheetChrome<Leading: View, Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SeamlySpace.s4) {
                HStack { leading() }.frame(maxWidth: .infinity, alignment: .leading)
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                HStack { trailing() }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.vertical, SeamlySpace.s4)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
            ScrollView { content() }
        }
        .background(SeamlyColor.paper)
        .presentationDragIndicator(.visible)
    }
}
