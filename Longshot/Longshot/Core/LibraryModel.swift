import CoreGraphics
import Foundation
import Observation
import StitchKit

/// One capture in the Library — a stored session plus its derived display state.
@MainActor
struct Capture: Identifiable {
    enum Phase: Equatable {
        case processing
        case ready
        case failed(String)
    }

    let session: StitchSession
    let folder: URL
    var phase: Phase = .processing
    /// Downscaled proxy for on-screen display (never the full-res stitch).
    var proxy: CGImage?

    var id: UUID { session.id }
    var isIncomplete: Bool { session.status == .recording }
    var flaggedSeamCount: Int { session.seams.filter(\.isLowConfidence).count }
}

/// The Library is the app's home surface and the source of truth for captures. It scans the
/// App Group on launch and foreground, imports finished sessions into app storage, and drives
/// assembly. `@MainActor` (UI state) with heavy work delegated off-actor.
@MainActor
@Observable
final class LibraryModel {
    private(set) var captures: [Capture] = []
    /// Set when the most recent pickup produced nothing stitchable, for a friendly nudge.
    private(set) var lastPickupWasEmpty = false

    private let appStore: SessionStore
    private let groupStore: SessionStore?

    init() {
        let appContainer = LibraryModel.appContainerURL()
        self.appStore = SessionStore(containerURL: appContainer)
        self.groupStore = AppGroup.containerURL.map { SessionStore(containerURL: $0) }
    }

    /// App-owned storage under Application Support.
    static func appContainerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Longshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Import finished captures from the App Group, then reload and assemble. Called on launch
    /// and every foreground — the scan, not the Darwin notification, is the source of truth.
    func refresh() async {
        lastPickupWasEmpty = await importFromGroup()
        reload()
        for capture in captures where capture.proxy == nil && capture.phase == .processing {
            await assemble(capture.id)
        }
    }

    /// Move stitchable sessions out of the shared container into app storage; discard the
    /// empty/no-scroll ones. Returns true if at least one imported session had nothing to stitch.
    private func importFromGroup() async -> Bool {
        guard let groupStore else { return false }
        let appStore = self.appStore
        return await Task.detached {
            var sawEmpty = false
            for session in groupStore.loadAll() {
                let source = groupStore.folder(for: session.id)
                // Never touch a session the extension may still be writing. Import when it's
                // cleanly finished, or when a `.recording` folder is stale enough that the
                // broadcast clearly crashed (so partial captures are still recovered).
                let manifest = groupStore.manifestURL(in: source)
                let finalized = session.status == .complete || Self.isStale(manifest)
                guard finalized else { continue }

                if session.hasStitchableContent {
                    let dest = appStore.folder(for: session.id)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.moveItem(at: source, to: dest)
                    } else {
                        try? FileManager.default.removeItem(at: source)
                    }
                } else {
                    sawEmpty = true
                    try? FileManager.default.removeItem(at: source)
                }
            }
            return sawEmpty
        }.value
    }

    /// A `.recording` manifest untouched for a while means the broadcast crashed rather than
    /// finished; such partial sessions are safe to import (and get badged incomplete).
    nonisolated private static func isStale(_ manifest: URL, olderThan seconds: TimeInterval = 90) -> Bool {
        guard let modified = try? FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) > seconds
    }

    private func reload() {
        let existing = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        captures = appStore.loadAll().map { session in
            if var prior = existing[session.id] { prior.phase == .ready ? () : (prior.phase = .processing); return prior }
            return Capture(session: session, folder: appStore.folder(for: session.id))
        }
    }

    /// Assemble (or re-assemble) one capture's proxy off the main actor.
    func assemble(_ id: UUID) async {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let session = captures[index].session
        let folder = captures[index].folder
        captures[index].phase = .processing

        let result: Result<CGImage, Error> = await Task.detached {
            do {
                let full = try StitchAssembler.composite(session, in: folder)
                return .success(StitchAssembler.makeProxy(full))
            } catch {
                return .failure(error)
            }
        }.value

        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success(let proxy):
            captures[index].proxy = proxy
            captures[index].phase = .ready
        case .failure(let error):
            captures[index].phase = .failed(error.localizedDescription)
        }
    }

    /// Composite the full-resolution image on demand (for export, not display).
    func fullComposite(_ id: UUID) async -> CGImage? {
        guard let capture = captures.first(where: { $0.id == id }) else { return nil }
        let session = capture.session, folder = capture.folder
        return await Task.detached { try? StitchAssembler.composite(session, in: folder) }.value
    }

    /// Render the capture to a PDF in a temp file for sharing.
    func exportPDF(_ id: UUID) async -> URL? {
        guard let capture = captures.first(where: { $0.id == id }) else { return nil }
        let session = capture.session, folder = capture.folder
        return await Task.detached {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Longshot-\(session.id.uuidString).pdf")
            do { try StitchAssembler.writePDF(session, in: folder, to: url); return url } catch { return nil }
        }.value
    }

    func delete(_ id: UUID) {
        try? appStore.delete(id)
        captures.removeAll { $0.id == id }
    }

    /// Persist an edited manifest and re-assemble the proxy.
    func update(_ session: StitchSession) async {
        guard let index = captures.firstIndex(where: { $0.id == session.id }) else { return }
        let folder = captures[index].folder
        try? SessionStore(containerURL: folder.deletingLastPathComponent().deletingLastPathComponent()).writeManifest(session)
        captures[index] = Capture(session: session, folder: folder, phase: .processing, proxy: captures[index].proxy)
        await assemble(session.id)
    }
}
