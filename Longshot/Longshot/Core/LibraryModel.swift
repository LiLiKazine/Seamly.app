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

    init(appContainer: URL = LibraryModel.appContainerURL(), groupContainer: URL? = AppGroup.containerURL) {
        self.appStore = SessionStore(containerURL: appContainer)
        self.groupStore = groupContainer.map { SessionStore(containerURL: $0) }
    }

    /// App-owned storage under Application Support.
    static func appContainerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Longshot", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            // Non-fatal: SessionStore recreates this lazily on the first write. Log so a
            // genuinely unwritable Application Support (rare) is diagnosable, not silent.
            print("Longshot: could not create app container: \(error)")
        }
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
            let fm = FileManager.default
            var sawEmpty = false
            do {
                // The destination's `sessions/` parent must exist or the `moveItem` below fails and
                // nothing ever imports — on a fresh install nothing else has created it yet.
                try fm.createDirectory(at: appStore.sessionsDirectory, withIntermediateDirectories: true)
            } catch {
                // Without this directory no import can succeed; there's no per-session recovery, so
                // log and bail rather than silently loop doing nothing.
                print("Longshot: could not create app sessions directory: \(error)")
                return false
            }
            for session in groupStore.loadAll() {
                let source = groupStore.folder(for: session.id)
                // Never touch a session the extension may still be writing. Import when it's
                // cleanly finished, or when a `.recording` folder is stale enough that the
                // broadcast clearly crashed (so partial captures are still recovered).
                let manifest = groupStore.manifestURL(in: source)
                let finalized = session.status == .complete || Self.isStale(manifest)
                guard finalized else { continue }

                do {
                    if session.hasStitchableContent {
                        let dest = appStore.folder(for: session.id)
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: source)   // already imported; drop the duplicate
                        } else {
                            try fm.moveItem(at: source, to: dest)
                        }
                    } else {
                        sawEmpty = true
                        try fm.removeItem(at: source)   // nothing to stitch; discard
                    }
                } catch {
                    // Skip this one session but keep importing the rest; a stuck session that
                    // silently disappears is exactly the failure we're guarding against.
                    print("Longshot: failed to import session \(session.id): \(error)")
                }
            }
            return sawEmpty
        }.value
    }

    /// A `.recording` manifest untouched for a while means the broadcast crashed rather than
    /// finished; such partial sessions are safe to import (and get badged incomplete).
    nonisolated private static func isStale(_ manifest: URL, olderThan seconds: TimeInterval = 90) -> Bool {
        // A missing or unreadable manifest can't be judged stale — treat it as not-stale so we
        // never import a folder that isn't a crashed recording. The throw here is expected
        // (e.g. the folder vanished mid-scan), so swallowing it is intentional.
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
        return await Task.detached {
            do {
                return try StitchAssembler.composite(session, in: folder)
            } catch {
                print("Longshot: full composite failed for \(session.id): \(error)")
                return nil
            }
        }.value
    }

    /// Render the capture to a PDF in a temp file for sharing.
    func exportPDF(_ id: UUID) async -> URL? {
        guard let capture = captures.first(where: { $0.id == id }) else { return nil }
        let session = capture.session, folder = capture.folder
        return await Task.detached {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Longshot-\(session.id.uuidString).pdf")
            do {
                try StitchAssembler.writePDF(session, in: folder, to: url)
                return url
            } catch {
                print("Longshot: PDF export failed for \(session.id): \(error)")
                return nil
            }
        }.value
    }

    func delete(_ id: UUID) {
        do {
            try appStore.delete(id)
        } catch {
            // Still drop it from the UI, but log: an undeletable folder would otherwise
            // reappear on the next scan as a silent ghost.
            print("Longshot: could not delete session \(id): \(error)")
        }
        captures.removeAll { $0.id == id }
    }

    /// Persist an edited manifest and re-assemble the proxy.
    func update(_ session: StitchSession) async {
        guard let index = captures.firstIndex(where: { $0.id == session.id }) else { return }
        let folder = captures[index].folder
        do {
            let store = SessionStore(containerURL: folder.deletingLastPathComponent().deletingLastPathComponent())
            try store.writeManifest(session)
        } catch {
            // The in-memory capture still updates and re-assembles below, but the edit won't
            // survive relaunch if this write fails. Log rather than silently lose it.
            print("Longshot: could not persist edited manifest for \(session.id): \(error)")
        }
        captures[index] = Capture(session: session, folder: folder, phase: .processing, proxy: captures[index].proxy)
        await assemble(session.id)
    }
}
