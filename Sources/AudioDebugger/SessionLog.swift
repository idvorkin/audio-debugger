import BugKit
import Foundation
import QuartzCore

/// Everything the app did, one JSON object per line, so a session can be reviewed from text (magic-monitor-native's
/// session log). Written to `~/Library/Application Support/AudioDebugger/logs/session-<start>.jsonl`.
///
/// Every line has `t` (wall clock, ISO 8601 with milliseconds, local zone), `mono` (seconds on the host clock) and
/// `type`. Thread-safe: callers on any queue.
final class SessionLog: @unchecked Sendable {
    static let shared = SessionLog()

    let url: URL
    private let queue = DispatchQueue(label: "com.idvorkin.audiodebugger.sessionlog", qos: .utility)
    private var handle: FileHandle?
    private let wallFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f
    }()

    /// Where the logs, bug reports (BugKit's `bugs.jsonl` and `bugs/`) and crash files live: on the Mac the bug-kit
    /// listener's `mac_dir`, on iOS the app's Documents, which the listener pulls from a paired device. A self-test
    /// keeps its own, `selftest/` inside it, so its scripted runs never get filed.
    static var root: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioDebugger", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        return Launch.scripted ? base.appendingPathComponent("selftest", isDirectory: true) : base
    }

    static var directory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    let startedAt = Date()

    private init() {
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        url = dir.appendingPathComponent("session-\(stamp.string(from: startedAt)).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    /// The newest 20 logs stay, and any a bug report names; the rest go (BugKit's `pruneLogs`).
    func prune() {
        BugStore(documents: Self.root).pruneLogs(keepNewest: 20, logger: bugLogger)
    }

    func event(_ type: String, _ fields: [String: Any] = [:]) {
        let now = Date(), mono = CACurrentMediaTime()
        queue.async { [self] in
            var line = fields.mapValues(Self.clean)
            line["t"] = wallFormat.string(from: now)
            line["mono"] = (mono * 1000).rounded() / 1000
            line["type"] = type
            guard JSONSerialization.isValidJSONObject(line),
                let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
            else { return }
            handle?.write(data)
            handle?.write(Data([0x0A]))
        }
    }

    /// Wait until every event logged so far is on disk (a bug report copies the file next).
    func flush() {
        queue.sync {}
    }

    /// This log's path under `root` and the milliseconds since it began: where a bug report points.
    var position: (path: String, tMs: Int) {
        ("logs/\(url.lastPathComponent)", Int(Date().timeIntervalSince(startedAt) * 1000))
    }

    /// BugKit's events (`bug_report`, `crash_report`, `logs_pruned`, `error`) into this log.
    var bugLogger: BugLogger { { [self] type, fields in event(type, fields.mapValues(\.foundation)) } }

    /// Doubles and Floats to 4 decimals (keeps lines short); nil to NSNull so optional fields read as null.
    private static func clean(_ value: Any) -> Any {
        switch value {
        case let d as Double: return d.isFinite ? (d * 10_000).rounded() / 10_000 : NSNull()
        case let f as Float: return clean(Double(f))
        case let a as [Any]: return a.map(clean)
        case let m as [String: Any]: return m.mapValues(clean)
        case Optional<Any>.none: return NSNull()
        default: return value
        }
    }
}
