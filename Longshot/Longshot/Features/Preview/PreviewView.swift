import SwiftUI
import StitchKit

/// The scrollable, zoomable preview of a finished capture. Displays the downscaled proxy
/// (never the full-res stitch — a GPU texture tops out ~16,384 px/side) and surfaces
/// confidence/segment warnings, with entries into editing and export.
struct PreviewView: View {
    let captureID: UUID
    let model: LibraryModel

    @State private var showEdit = false
    @State private var showExport = false
    @State private var zoom: CGFloat = 1

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    var body: some View {
        Group {
            if let capture {
                content(capture)
            } else {
                ContentUnavailableView("Capture removed", systemImage: "photo.badge.exclamationmark")
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let capture, capture.phase == .ready {
                ToolbarItem(placement: .primaryAction) {
                    Button("Export", systemImage: "square.and.arrow.up") { showExport = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Edit", systemImage: "slider.horizontal.3") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let capture { EditView(session: capture.session, model: model) }
        }
        .sheet(isPresented: $showExport) {
            ExportView(captureID: captureID, model: model)
        }
    }

    @ViewBuilder
    private func content(_ capture: Capture) -> some View {
        switch capture.phase {
        case .processing:
            VStack(spacing: 12) { ProgressView(); Text("Stitching…").foregroundStyle(.secondary) }
        case .failed(let message):
            ContentUnavailableView("Couldn't stitch", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            VStack(spacing: 0) {
                warnings(capture)
                ScrollView([.vertical, .horizontal]) {
                    if let proxy = capture.proxy {
                        Image(decorative: proxy, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .gesture(MagnifyGesture().onChanged { zoom = max(1, $0.magnification) }.onEnded { _ in
                                withAnimation { zoom = max(1, min(zoom, 6)) }
                            })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func warnings(_ capture: Capture) -> some View {
        let breaks = capture.session.segmentBreaks.count
        let lowBands = capture.lowConfidenceBandCount
        if capture.isIncomplete || capture.flaggedSeamCount > 0 || breaks > 0 || lowBands > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if capture.isIncomplete {
                    Label("Incomplete capture — stitched from what was saved.", systemImage: "exclamationmark.circle")
                }
                if lowBands > 0 {
                    Label("\(lowBands) section(s) with uncertain bars — tap Edit to set the crop.", systemImage: "rectangle.dashed")
                }
                if capture.flaggedSeamCount > 0 {
                    Label("\(capture.flaggedSeamCount) seam(s) flagged. Tap Edit to fine-tune.", systemImage: "flag")
                }
                if breaks > 0 {
                    Label("\(breaks) gap(s) from fast scrolling.", systemImage: "scissors")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.yellow.opacity(0.12))
        }
    }
}
