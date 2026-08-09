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
    /// Segments whose chrome band didn't lock confidently — composited whole-frame (chrome may
    /// repeat) and awaiting an editor override. Surfaced so the failure isn't silent.
    var lowConfidenceBandCount: Int { session.contentBands.filter(\.isLowConfidence).count }
    /// Scroll order used the input-order fallback for Photos or broadcast rather than recovery.
    var orderAssumed: Bool { session.orderAssumed }
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
    /// 0…1 while a video import decodes; nil when idle. Drives a determinate progress view.
    private(set) var importProgress: Double?
    /// Set when the most recent import failed, for a user-visible message.
    private(set) var importError: String?

    private let appStore: SessionStore
    private let groupStore: SessionStore?
    private let groupContainer: URL?
    private let diag: Diagnostics

    init(appContainer: URL = LibraryModel.appContainerURL(), groupContainer: URL? = AppGroup.containerURL) {
        self.appStore = SessionStore(containerURL: appContainer)
        self.groupStore = groupContainer.map { SessionStore(containerURL: $0) }
        self.groupContainer = groupContainer
        self.diag = Diagnostics(containerURL: groupContainer, category: .app)
    }

    /// App-owned storage under Application Support.
    static func appContainerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seamly", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            // Non-fatal: SessionStore recreates this lazily on the first write. Log so a
            // genuinely unwritable Application Support (rare) is diagnosable, not silent.
            print("Seamly: could not create app container: \(error)")
        }
        return base
    }

    /// Import finished captures from the App Group, then reload and assemble. Called on launch
    /// and every foreground — the scan, not the Darwin notification, is the source of truth.
    func refresh() async {
        diag.log("refresh: begin (group=\(groupContainer != nil ? "resolved" : "NIL"))")
        lastPickupWasEmpty = await importFromGroup()
        reload()
        diag.log("refresh: \(captures.count) capture(s) after import; \(captures.filter { $0.phase == .processing }.count) to assemble")
        for capture in captures where capture.proxy == nil && capture.phase == .processing {
            await assemble(capture.id)
        }
    }

    /// Clear a previously surfaced import error (e.g. once the user has seen/dismissed it).
    func clearImportError() {
        importError = nil
    }

    /// Import picked screenshots as a new capture. Recovers scroll order from overlap, falling back
    /// to the pick order (badged) only when recovery can't chain them into one segment — pick order
    /// is a guess, so it must not override an order the pixels actually settled.
    func importPhotos(_ images: [CGImage]) async {
        await runImport { store, diag in
            try MediaImporter.write(images: images, into: store, strategy: .recoverOrInputOrder, source: .photos, diag: diag)
        }
    }

    /// Import one screen recording as a new capture: decode it into keyframes through the real
    /// capture driver (sampled 30 fps — the validated cadence from Task 3), then stitch in capture order.
    func importVideo(_ url: URL) async {
        importProgress = 0
        let diag = self.diag
        defer {
            // `PickedMovie` copied the recording into tmp/ purely so AVAssetReader could open it;
            // decoding is done by the time this returns, so the copy is ours to drop. These are
            // large, and while tmp/ is OS-purgeable they otherwise accumulate for the whole session.
            do { try FileManager.default.removeItem(at: url) }
            catch { diag.log("importVideo: temp cleanup failed: \(error.localizedDescription)") }
        }
        // A `@Sendable` sink that hops each fraction back to the main actor to update UI state.
        let sink: @Sendable (Double) -> Void = { [weak self] frac in
            Task { @MainActor in self?.importProgress = frac }
        }
        let decoded: Result<[CGImage], Error> = await Task.detached {
            do {
                var driver = ScrollCaptureDriver()
                let r = try await VideoKeyframeSource.decodeCommittedKeyframes(
                    url: url, driver: &driver, targetFPS: 30, progress: sink
                )
                diag.log("importVideo: \(r.frames) frames, \(r.decodeFailures) decode failures, \(r.keyframes.count) keyframes")
                return .success(r.keyframes.map { $0.image })
            } catch {
                return .failure(error)
            }
        }.value
        importProgress = nil
        switch decoded {
        case .failure(let error):
            importError = error.localizedDescription
            diag.log("importVideo: decode FAILED: \(error.localizedDescription)")
        case .success(let images):
            await runImport { store, diag in
                try MediaImporter.write(images: images, into: store, strategy: .inputOrder, source: .video, diag: diag)
            }
        }
    }

    /// Shared tail: run a `MediaImporter.write` off-main, then reload + assemble the new capture, or
    /// record a user-visible error. `.notEnoughContent` maps to the friendly empty nudge.
    private func runImport(_ body: @escaping @Sendable (SessionStore, Diagnostics) throws -> UUID) async {
        let store = appStore
        let diag = self.diag
        let result: Result<UUID, Error> = await Task.detached {
            do { return .success(try body(store, diag)) }
            catch { return .failure(error) }
        }.value
        switch result {
        case .success(let id):
            reload()
            await assemble(id)
        case .failure(let error):
            if case MediaImporter.ImportError.notEnoughContent = error {
                lastPickupWasEmpty = true
            } else {
                importError = error.localizedDescription
            }
            diag.log("import: FAILED: \(error.localizedDescription)")
        }
    }

    /// Move stitchable sessions out of the shared container into app storage; discard the
    /// empty/no-scroll ones. Returns true if at least one imported session had nothing to stitch.
    private func importFromGroup() async -> Bool {
        guard let groupStore else { diag.log("import: no group store (App Group unavailable)"); return false }
        let appStore = self.appStore
        let diag = self.diag
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
                diag.log("import: FAILED to create app sessions dir: \(error.localizedDescription)")
                return false
            }
            let sessions = groupStore.loadAll()
            diag.log("import: \(sessions.count) readable session(s) in group")
            for session in sessions {
                let source = groupStore.folder(for: session.id)
                // Never touch a session the extension may still be writing. Import when it's
                // cleanly finished, or when a `.recording` folder is stale enough that the
                // broadcast clearly crashed (so partial captures are still recovered).
                let manifest = groupStore.manifestURL(in: source)
                let finalized = session.status == .complete || Self.isStale(manifest)
                let shortID = session.id.uuidString.prefix(8)
                diag.log("import: \(shortID) status=\(session.status.rawValue) keyframes=\(session.keyframes.count) finalized=\(finalized) stitchable=\(session.hasStitchableContent)")
                guard finalized else {
                    diag.log("import: \(shortID) SKIPPED (not finalized — still recording and not yet stale)")
                    continue
                }

                do {
                    if session.hasStitchableContent {
                        let dest = appStore.folder(for: session.id)
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: source)   // already imported; drop the duplicate
                            diag.log("import: \(shortID) duplicate dropped (already in app storage)")
                        } else {
                            try fm.moveItem(at: source, to: dest)
                            diag.log("import: \(shortID) IMPORTED into app storage")
                            // Resolve scroll order + geometry once, now, so the manifest the app
                            // composites (and the user edits) is correct. The extension's live
                            // seams/bands are unreliable; re-derive them from the keyframes.
                            //
                            // Its *order*, however, is trustworthy: `ScrollCaptureDriver` numbers
                            // keyframes monotonically as it banks them, so a broadcast's stored
                            // order is capture order — the same temporal ordering that justifies
                            // `.inputOrder` for video. So recovery gets first refusal, and only
                            // when it leaves segment breaks do we fall back to capture order and
                            // badge `orderAssumed`. Fallback preserves those genuine breaks; seam
                            // confidence alone never changes the ordering policy.
                            do {
                                let resolved = try StitchAssembler.resolveGeometry(session, in: dest, strategy: .recoverOrInputOrder)
                                try appStore.writeManifest(resolved)
                                diag.log("import: \(shortID) geometry resolved (\(resolved.keyframes.count) kf, \(resolved.seams.count) seams, \(resolved.segmentBreaks.count) breaks, orderAssumed=\(resolved.orderAssumed))")
                            } catch {
                                // Non-fatal: keep the extension's manifest so the capture still
                                // imports (it may stitch imperfectly) rather than being lost.
                                diag.log("import: \(shortID) geometry resolve FAILED, keeping extension manifest: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        sawEmpty = true
                        try fm.removeItem(at: source)   // nothing to stitch; discard
                        diag.log("import: \(shortID) discarded (no stitchable content)")
                    }
                } catch {
                    // Skip this one session but keep importing the rest; a stuck session that
                    // silently disappears is exactly the failure we're guarding against.
                    diag.log("import: \(shortID) FAILED to import: \(error.localizedDescription)")
                }
            }
            return sawEmpty
        }.value
    }

    /// A `.recording` manifest untouched for a while means the broadcast ended without a clean
    /// `broadcastFinished` (the extension is often killed under its ~50 MB memory ceiling before
    /// it can finalize), so such partial sessions are imported anyway and badged incomplete.
    ///
    /// The window is a trade-off: too long and a killed capture sits invisible (the 90 s we used
    /// to have meant an 11-minute wait in practice); too short and we could move a folder out from
    /// under an extension that's merely paused mid-scroll. The extension checkpoints its manifest
    /// on every keyframe, and the app only ever scans while *foregrounded* (i.e. after the user has
    /// left the recorded app), so ~20 s of no writes is a confident "the broadcast is over" signal.
    nonisolated private static func isStale(_ manifest: URL, olderThan seconds: TimeInterval = 20) -> Bool {
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
            diag.log("assemble: \(id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
            captures[index].phase = .failed(error.localizedDescription)
        }
    }

    /// Composite the full-resolution image on demand (for export, not display).
    func fullComposite(_ id: UUID) async -> CGImage? {
        guard let capture = captures.first(where: { $0.id == id }) else { return nil }
        let session = capture.session, folder = capture.folder
        let diag = self.diag
        return await Task.detached {
            do {
                return try StitchAssembler.composite(session, in: folder)
            } catch {
                diag.log("fullComposite: \(session.id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    /// Render the capture to a PDF in a temp file for sharing.
    func exportPDF(_ id: UUID) async -> URL? {
        guard let capture = captures.first(where: { $0.id == id }) else { return nil }
        let session = capture.session, folder = capture.folder
        let diag = self.diag
        return await Task.detached {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Seamly-\(session.id.uuidString).pdf")
            do {
                try StitchAssembler.writePDF(session, in: folder, to: url)
                return url
            } catch {
                diag.log("exportPDF: \(session.id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
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
            diag.log("delete: \(id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
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
            diag.log("update: \(session.id.uuidString.prefix(8)) manifest persist FAILED: \(error.localizedDescription)")
        }
        captures[index] = Capture(session: session, folder: folder, phase: .processing, proxy: captures[index].proxy)
        await assemble(session.id)
    }
}
