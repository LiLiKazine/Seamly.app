import SwiftUI

/// Every capture. Compact is a ruled list; regular is a grid of uniform 3:5 cells. The dock
/// stays, because the capture affordance is permanently present.
struct LibraryScreen: View {
    let model: CaptureModel
    var onOpen: (UUID) -> Void
    var onBack: () -> Void
    var onVideo: () -> Void
    var onPhotos: () -> Void
    var onDiagnostics: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "Library",
                subtitle: "\(model.captures.count) captures",
                large: true,
                onBack: onBack
            ) {
                // Diagnostics is a developer surface, not a feature. It stays reachable
                // because the extension cannot draw UI and its container is not reliably
                // pullable over USB, so this log is the only window into a failed capture on a
                // device — but it lives behind an overflow, on the screen that already holds
                // everything else.
                Menu {
                    Button("Diagnostics", systemImage: "stethoscope", action: onDiagnostics)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .seamlyHitTarget()
                }
                .accessibilityLabel("More")
            }

            if model.captures.isEmpty {
                EmptyState(
                    symbol: "tray",
                    title: "No captures yet",
                    message: "Anything you record or import shows up here."
                )
                .frame(maxHeight: .infinity)
            } else if layout.isRegular {
                grid
            } else {
                list
            }

            CaptureDock(onVideo: onVideo, onPhotos: onPhotos)
                .padding(.horizontal, layout.gutter)
                .padding(.top, SeamlySpace.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    private var list: some View {
        List {
            ForEach(model.captures) { capture in
                CaptureListRow(
                    capture: capture,
                    onOpen: { onOpen(capture.id) },
                    onDelete: { model.delete(capture.id) }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(SeamlyColor.paper)
            }
            Section {
                ImportRow(symbol: "film", title: "From Video",
                          detail: "Stitch an existing screen recording", action: onVideo)
                ImportRow(symbol: "photo.on.rectangle", title: "From Photos",
                          detail: "Pick overlapping screenshots", action: onPhotos)
            } header: {
                Text("Or start from something you already have".uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(SeamlyColor.paper)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SeamlyColor.paper)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: SeamlySpace.s7)],
                spacing: SeamlySpace.s7
            ) {
                ForEach(model.captures) { capture in
                    CaptureGridCard(
                        capture: capture,
                        onOpen: { onOpen(capture.id) },
                        onDelete: { model.delete(capture.id) }
                    )
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s8)
        }
    }
}
