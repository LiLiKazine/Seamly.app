import SwiftUI
import StitchKit

/// The app's home surface: the Library of captures. Scans the App Group on appear and every
/// foreground so a just-finished broadcast shows up as a new capture (processing → ready).
struct LibraryView: View {
    @State private var model = LibraryModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var showOnboarding = false
    @State private var showCapture = false
    @State private var showEmptyNudge = false
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            Group {
                if model.captures.isEmpty {
                    ScrollView { CaptureStartView(model: model, showHelp: { showOnboarding = true }).frame(maxWidth: .infinity).padding(.top, 60) }
                } else {
                    List {
                        ForEach(model.captures) { capture in
                            NavigationLink(value: capture.id) {
                                CaptureRow(capture: capture)
                            }
                        }
                        .onDelete { indices in
                            for index in indices { model.delete(model.captures[index].id) }
                        }
                    }
                }
            }
            .navigationTitle("Seamly")
            .navigationDestination(for: UUID.self) { id in
                PreviewView(captureID: id, model: model)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Capture", systemImage: "plus.viewfinder") { showCapture = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Help", systemImage: "questionmark.circle") { showOnboarding = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                }
            }
        }
        .task {
            if !hasSeenOnboarding { showOnboarding = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh(); showEmptyNudge = model.lastPickupWasEmpty } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh(); showEmptyNudge = model.lastPickupWasEmpty }
        }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .sheet(isPresented: $showCapture) {
            CaptureStartView(model: model, showHelp: { showOnboarding = true }, onStarted: { showCapture = false })
                .presentationDetents([.medium])
        }
        .alert("Nothing to stitch", isPresented: $showEmptyNudge) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That capture had no scrolling to stitch — did you scroll the other app?")
        }
        .overlay(alignment: .bottom) {
            if let p = model.importProgress {
                VStack(spacing: 6) {
                    ProgressView(value: p) { Text("Reading video…") }
                    Text("\(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
                }
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            }
        }
        .alert("Import failed", isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.clearImportError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }
}

/// One row in the Library list: a thumbnail plus status.
struct CaptureRow: View {
    let capture: Capture

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 64)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.session.createdAt, style: .date).font(.headline)
                statusLabel
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let proxy = capture.proxy {
            // A long screenshot is very tall; a center `scaledToFill` crop shows a confusing
            // middle slice that reads as "not stitched". Fill the width and anchor to the top so
            // the recognizable start of the capture (status bar / first content) is what shows.
            Image(decorative: proxy, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 64, alignment: .top)
                .clipped()
        } else {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch capture.phase {
        case .processing:
            Label("Processing…", systemImage: "gearshape").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
        case .ready:
            HStack(spacing: 8) {
                if capture.isIncomplete { Label("Incomplete", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                if capture.flaggedSeamCount > 0 { Label("\(capture.flaggedSeamCount)", systemImage: "flag") }
                if capture.orderAssumed { Label("Order assumed", systemImage: "arrow.up.arrow.down").foregroundStyle(.orange) }
                Text("Ready").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}
