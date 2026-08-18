import SwiftUI
import StitchKit

/// The app's home: a record affordance, not a list.
///
/// Seamly is one-shot — you record, you get your screenshot, you save it. A finished capture
/// navigates to *itself* via `CaptureModel.pendingResult` rather than appearing as a row the
/// user has to notice and tap.
struct HomeView: View {
    @State private var model = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var path: [UUID] = []
    @State private var showOnboarding = false
    @State private var showDiagnostics = false
    @State private var showNothingToStitch = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 32) {
                    recordSection
                    Divider()
                    importSection
                    if !model.captures.isEmpty { recents }
                }
                .padding()
            }
            .navigationTitle("Seamly")
            .navigationDestination(for: UUID.self) { id in
                ResultView(captureID: id, model: model, onRecordAgain: { path.removeAll() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("How it works", systemImage: "questionmark.circle") { showOnboarding = true }
                }
                // Diagnostics is a developer surface, not a feature — tucked behind a menu
                // rather than given a top-level button. It stays reachable because the
                // extension cannot draw UI and its container is not reliably pullable over
                // USB, so this log is the only window into a failed capture on a device.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if model.importProgress != nil || model.isAssemblingNewArrival {
                    ProcessingView(progress: model.importProgress)
                        .background(.regularMaterial)
                }
            }
        }
        .task {
            if !hasSeenOnboarding { showOnboarding = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh() }
        }
        // The model finished assembling an import: go straight to it, then clear the trigger
        // so navigating back doesn't re-push the same destination.
        .onChange(of: model.pendingResult) { _, id in
            guard let id else { return }
            path = [id]
            model.consumePendingResult()
        }
        // React to the flag being *set*, not to it changing: `lastPickupWasEmpty` is an event,
        // and consuming it immediately (mirroring `consumePendingResult()`) is what lets a
        // second consecutive empty pickup set it `true` again and fire this a second time.
        .onChange(of: model.lastPickupWasEmpty) { _, empty in
            guard empty else { return }
            showNothingToStitch = true
            model.consumeLastPickupWasEmpty()
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showNothingToStitch) {
            NothingToStitchView(onRecordAgain: { showNothingToStitch = false })
                .presentationDetents([.medium])
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.clearImportError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }

    private var recordSection: some View {
        VStack(spacing: 16) {
            // `RPSystemBroadcastPickerView` draws a fixed *black* glyph in both appearances —
            // it does not adapt, and reaching into its private subviews to restyle it is the
            // fragility `BroadcastPickerButton` refuses. So the backing has to carry the
            // contrast on its own: a solid accent disc, which stays bright against a black
            // background. A 15%-opacity tint read as a barely-there smudge in dark mode.
            ZStack {
                Circle().fill(.tint).frame(width: 120, height: 120)
                BroadcastPickerButton().frame(width: 100, height: 100)
            }
            Text("Record a long screenshot").font(.headline)
            Text("Pick Seamly, switch to the app you want, and scroll down steadily. One buzz means ease up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var importSection: some View {
        VStack(spacing: 12) {
            Text("Already have it?").font(.caption).foregroundStyle(.secondary)
            VideoImportButton(model: model)
            PhotoImportButton(model: model)
        }
    }

    /// Recent captures — a way back to something you just made and haven't saved, not a
    /// library. Every stored capture appears: capping the strip would strand older captures
    /// on disk with no way to reach or delete them. Long-press deletes; nothing is ever
    /// removed without a tap.
    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.captures) { capture in
                        Button {
                            path = [capture.id]
                        } label: {
                            thumbnail(capture)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recent-capture")
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                model.delete(capture.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func thumbnail(_ capture: Capture) -> some View {
        Group {
            if let proxy = capture.proxy {
                // A long screenshot is very tall; a centred crop shows a confusing middle
                // slice that reads as "not stitched". Anchor to the top so the recognizable
                // start of the capture is what shows.
                Image(decorative: proxy, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 96, alignment: .top)
                    .clipped()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .frame(width: 72, height: 96)
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Without this, the button's hit-test *and* accessibility frame follow the aspect-filled
        // image's own unclipped render size rather than this 72×96 box — `.clipped()` above only
        // affects painting. Harmless to miss on a normal, close-to-72:96 screenshot, but a long
        // stitched capture is far more extreme (many screens tall, ~72 wide), so the mismatch grows
        // with it: found by driving a real tap at the thumbnail's *reported* center, which landed
        // well below the visible thumbnail and hit nothing — see docs/logs/2026-08-18-02-guided-repair.md.
        .contentShape(Rectangle())
        .accessibilityLabel(Text(capture.session.createdAt, style: .date))
    }
}
