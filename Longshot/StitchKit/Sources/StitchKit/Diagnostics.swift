import Foundation
import os

/// Cross-process diagnostic logging shared by the app and the broadcast extension.
///
/// Two channels, always both attempted, because each covers a case the other can't:
/// - **Unified log** (`os.Logger`, subsystem `io.github.lilikazine.Longshot`): real-time,
///   visible in Console.app / `log stream` while a Mac is attached.
/// - **Durable file** (`<container>/diagnostics.log`): survives with no cable and is readable
///   back inside the app, so a user can hand over a trace after the fact. This is the only
///   channel that works for the extension, which can't present UI and whose App Group container
///   isn't reliably pullable over USB.
///
/// Given only a container URL (the app and extension each resolve their shared App Group and hand
/// it in), so StitchKit stays free of the hardcoded group identifier — same pattern as
/// `SessionStore`. The file is size-capped so it's a permanent facility, not a throwaway probe.
public struct Diagnostics: Sendable {
    public enum Category: String, Sendable {
        case capture   // the broadcast extension
        case app       // the app (import, assembly, export)
    }

    /// Legacy filename kept only so a trace written before this facility existed is still
    /// readable via `readAll`. New writes always go to `logFilename`.
    static let legacyFilename = "broadcast-debug.log"
    static let logFilename = "diagnostics.log"

    /// Above this the file is trimmed to its most recent `keepBytes`, so an unbounded broadcast
    /// can't grow it without limit while still leaving plenty of recent history.
    private static let capBytes = 512 * 1024
    private static let keepBytes = 256 * 1024

    private let fileURL: URL?
    private let logger: Logger
    private let categoryTag: String

    public init(containerURL: URL?, category: Category) {
        self.fileURL = containerURL?.appendingPathComponent(Self.logFilename)
        self.logger = Logger(subsystem: "io.github.lilikazine.Longshot", category: category.rawValue)
        self.categoryTag = category.rawValue
    }

    /// Record one event on both channels. Best-effort: never throws, never crashes a broadcast.
    public func log(_ message: String) {
        // Unified log first, so there is always at least one channel even if the file write below
        // fails — that failure would otherwise be undiagnosable (we can't log a logging failure).
        logger.log("\(message, privacy: .public)")

        guard let fileURL else { return }
        let line = "\(Self.timestamp()) [\(categoryTag)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
            Self.capIfNeeded(fileURL)
        } catch {
            // Best-effort: the event already reached the unified log above, so dropping the file
            // append here is acceptable rather than propagating into the broadcast/import path.
            logger.error("diagnostics file append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reading back (app side)

    /// The full recorded trace — legacy file first, then the current one — for display/sharing in
    /// the app. Returns a friendly placeholder when nothing has been recorded yet.
    public static func readAll(containerURL: URL) -> String {
        var out = ""
        for name in [legacyFilename, logFilename] {
            let url = containerURL.appendingPathComponent(name)
            // A missing log file is the normal "nothing recorded yet" case, so a failed read here
            // is expected-benign and intentionally skipped rather than surfaced.
            guard let contents = try? String(contentsOf: url, encoding: .utf8), !contents.isEmpty else { continue }
            out += "===== \(name) =====\n\(contents)\n"
        }
        return out.isEmpty ? "(no diagnostics recorded yet)" : out
    }

    /// Delete both log files. Throws so the caller can surface a failed clear rather than leaving
    /// the user staring at a log that won't empty.
    public static func clear(containerURL: URL) throws {
        let fm = FileManager.default
        for name in [legacyFilename, logFilename] {
            let url = containerURL.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Internals

    private static func capIfNeeded(_ url: URL) {
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > capBytes else { return }
            let data = try Data(contentsOf: url)
            let tail = data.suffix(keepBytes)
            // Start at the first newline inside the kept tail so the file never begins with a
            // half-line; fall back to the raw tail if there is no newline.
            let start = tail.firstIndex(of: 0x0A).map { tail.index(after: $0) } ?? tail.startIndex
            let trimmed = Data("[…trimmed…]\n".utf8) + tail[start...]
            try trimmed.write(to: url, options: .atomic)
        } catch {
            // Trimming is housekeeping; if it fails the log simply keeps growing until the next
            // successful pass. Not worth propagating.
        }
    }

    private static func timestamp() -> String {
        Date().formatted(timestampStyle)
    }

    // ISO-8601 with fractional seconds. A `Date.ISO8601FormatStyle` is a Sendable value type, so
    // it's safe to hold as a static (unlike `ISO8601DateFormatter`).
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
