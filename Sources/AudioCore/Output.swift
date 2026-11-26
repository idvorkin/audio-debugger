/// Story 020: a device replay can play on (the Mac's Core Audio outputs: `Mics.outputs()` in Mac/Mics+Mac.swift).
public struct Output: Identifiable, Hashable, Sendable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }

    public var id: String { uid }
}

/// The replay's output, chosen apart from the mic: `wanted` is the remembered choice (nil: the system default).
/// A wanted output that is not plugged in is kept, so it is used again when it returns; meanwhile replay plays on the
/// system default and `missing` says so.
public struct OutputChoice: Equatable, Sendable {
    public let wanted: String?
    public let outputs: [Output]

    public init(wanted: String?, outputs: [Output]) {
        self.wanted = wanted
        self.outputs = outputs
    }

    /// The output to play on now; nil is the system default.
    public var active: Output? { wanted.flatMap { uid in outputs.first { $0.uid == uid } } }

    /// Chosen, but not plugged in.
    public var missing: Bool { wanted != nil && active == nil }

    /// O: the system default, then each output in turn, then the default again.
    public func next() -> OutputChoice {
        guard let current = active, let i = outputs.firstIndex(of: current) else {
            return OutputChoice(wanted: outputs.first?.uid, outputs: outputs)
        }
        let after = outputs.index(after: i)
        return OutputChoice(wanted: after < outputs.endIndex ? outputs[after].uid : nil, outputs: outputs)
    }
}
