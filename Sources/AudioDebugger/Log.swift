import os

/// `just logs` streams these; `just selftest` prints them.
enum Log {
    private static let subsystem = "com.idvorkin.audiodebugger"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let mic = Logger(subsystem: subsystem, category: "mic")
    static let level = Logger(subsystem: subsystem, category: "level")
    static let replay = Logger(subsystem: subsystem, category: "replay")
    static let selftest = Logger(subsystem: subsystem, category: "selftest")
}
