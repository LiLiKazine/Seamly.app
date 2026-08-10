import Foundation

/// Manages the on-disk layout of capture sessions: one folder per session under
/// `<container>/sessions/<uuid>/`, each holding keyframe files and a `manifest.json`.
///
/// Given only a base container URL, `SessionStore` knows nothing about App Groups — the app
/// and the extension resolve their shared container and hand it in, keeping StitchKit free of
/// platform specifics. Reads tolerate partially-written sessions (a crash leaves the manifest
/// `recording`); such sessions are still returned so the app can stitch and badge them.
public struct SessionStore: Sendable {
    /// `<container>/sessions`.
    public let sessionsDirectory: URL

    public init(containerURL: URL) {
        self.sessionsDirectory = containerURL.appendingPathComponent("sessions", isDirectory: true)
    }

    public func folder(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    public func createFolder(for id: UUID) throws -> URL {
        let url = folder(for: id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func manifestURL(in folder: URL) -> URL {
        folder.appendingPathComponent("manifest.json")
    }

    public func keyframeURL(_ keyframe: Keyframe, in folder: URL) -> URL {
        folder.appendingPathComponent(keyframe.filename)
    }

    /// Write a manifest atomically into the session's folder (creating it if needed).
    public func writeManifest(_ session: StitchSession) throws {
        try session.validateKeyframeChrome()
        let dir = try createFolder(for: session.id)
        let data = try encoder.encode(session)
        try data.write(to: manifestURL(in: dir), options: .atomic)
    }

    public func readManifest(for id: UUID) throws -> StitchSession {
        try readManifest(at: manifestURL(in: folder(for: id)))
    }

    public func readManifest(at url: URL) throws -> StitchSession {
        let data = try Data(contentsOf: url)
        let session = try decoder.decode(StitchSession.self, from: data)
        try session.validateKeyframeChrome()
        return session
    }

    /// All sessions currently on disk, newest first. Folders without a readable manifest are
    /// skipped rather than throwing, so one corrupt session never hides the rest.
    public func loadAll() -> [StitchSession] {
        let fm = FileManager.default
        // No sessions directory yet (fresh install, before any write) is the expected empty
        // case, so swallowing the throw and returning [] here is intentional.
        guard let entries = try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let sessions = entries.compactMap { entry -> StitchSession? in
            try? readManifest(at: manifestURL(in: entry))
        }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: folder(for: id))
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
