import SwiftUI
import StitchKit

/// Where the app goes. Home is the root, because the app opens on the most recent capture.
enum Route: Hashable {
    case library
    case review(UUID)
}

/// The one place the model is owned, the navigation stack lives, and every model-driven
/// presentation is decided. Screens take closures and know nothing about routing.
struct AppShell: View {
    @State private var model = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var path: [Route] = []
    @State private var showFirstRun = false
    @State private var showDiagnostics = false
    @State private var showNothingToStitch = false

    /// A join to open the repair on. A wrapper rather than a bare `Int` so
    /// `fullScreenCover(item:)` can identify it.
    struct RepairTarget: Identifiable, Hashable {
        let captureID: UUID
        let findingNumber: Int
        var id: String { "\(captureID)-\(findingNumber)" }
    }

    @State private var repairTarget: RepairTarget?

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                model: model,
                onLibrary: { path.append(.library) },
                onReview: { path.append(.review($0)) },
                onRepair: { repairTarget = RepairTarget(captureID: $0, findingNumber: $1) },
                onHelp: { showFirstRun = true },
                onVideo: {},
                onPhotos: {}
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(route).toolbar(.hidden, for: .navigationBar)
            }
        }
        .task {
            if !hasSeenOnboarding { showFirstRun = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh() }
        }
        // A new arrival — including a failed one, per DECISIONS.md [B4] — pops to Home rather
        // than pushing. Under return-home, Home IS the answer to "what did I get?"; pushing a
        // screen over it would bury the thing the user came back for.
        .onChange(of: model.pendingResult) { _, id in
            guard id != nil else { return }
            path.removeAll()
            model.consumePendingResult()
        }
        // React to the flag being *set*, not to it changing: `lastPickupWasEmpty` is an event,
        // and consuming it immediately is what lets a second consecutive empty pickup set it
        // `true` again and fire this a second time.
        .onChange(of: model.lastPickupWasEmpty) { _, empty in
            guard empty else { return }
            showNothingToStitch = true
            model.consumeLastPickupWasEmpty()
        }
        .sheet(isPresented: $showFirstRun) { OnboardingView() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showNothingToStitch) {
            nothingToStitch.presentationDetents([.medium])
        }
        .fullScreenCover(item: $repairTarget) { target in
            RepairQueueView(
                captureID: target.captureID,
                model: model,
                startAt: target.findingNumber,
                onClose: { repairTarget = nil }
            )
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

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .library:
            // Replaced by LibraryScreen in Task 15.
            EmptyState(symbol: "list.bullet", title: "Library")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SeamlyColor.paper)
        case .review(let id):
            ReviewScreen(
                captureID: id,
                model: model,
                onBack: { path.removeLast() },
                onRepair: { repairTarget = RepairTarget(captureID: id, findingNumber: $0) },
                onExport: {}
            )
        }
    }

    @ViewBuilder
    private var nothingToStitch: some View {
        EmptyState(
            symbol: "arrow.up.and.down",
            title: "Nothing to stitch",
            message: "This recording didn't scroll, so there was nothing to join together. Start the recording, switch to the app you want, then scroll down steadily."
        ) {
            SeamlyButton("Record again") { showNothingToStitch = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }
}
