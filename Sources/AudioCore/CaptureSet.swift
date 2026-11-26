import Foundation

/// Stories 017-019: a capture set's `manifest.json`. Every mic's take of the same moment (together) or the same phrase
/// (in turn), one WAV and one sample sidecar each beside it; this says which mic each is, its rate, and how the streams
/// line up. Spec: docs/specs/2026-11-26-compare-mics.md.
public struct CaptureSet: Codable, Equatable, Sendable {
    public static let version = 1
    public static let phrase = "Six thick thistle sticks. A quick brown fox jumps over the lazy dog."

    public enum Mode: String, Codable, Sendable {
        /// M: every mic at once, except Bluetooth (opening AirPods drops them into call mode) and Continuity iPhones
        /// (opening one wakes the phone).
        case together
        /// ⇧M: each mic in turn, all of them, the same phrase each time.
        case inTurn

        /// The mics this mode records, in list order; `matching` (a scripted run's filter) keeps those whose name
        /// contains it, ignoring case.
        public func mics(from all: [Mic], matching filter: String? = nil) -> [Mic] {
            all.filter { mic in
                (self == .inTurn || (mic.kind != .bluetooth && mic.kind != .continuity))
                    && (filter.map { mic.name.localizedCaseInsensitiveContains($0) } ?? true)
            }
        }
    }

    public struct Stream: Codable, Equatable, Sendable {
        public var index: Int
        public var name: String
        public var uid: String
        public var kind: Mic.Kind
        /// Absent when the mic failed.
        public var rate: Double?
        public var file: String?
        /// Seconds after the earliest stream's start (together); 0 in turn.
        public var offset: Double?
        /// When the stream's first sample arrived, in seconds since boot (`systemUptime`).
        public var started: Double?
        public var openMs: Int?
        /// Why the mic gave no stream, in words.
        public var error: String?

        public init(
            index: Int, name: String, uid: String, kind: Mic.Kind, rate: Double? = nil, file: String? = nil,
            offset: Double? = nil, started: Double? = nil, openMs: Int? = nil, error: String? = nil
        ) {
            self.index = index
            self.name = name
            self.uid = uid
            self.kind = kind
            self.rate = rate
            self.file = file
            self.offset = offset
            self.started = started
            self.openMs = openMs
            self.error = error
        }
    }

    public enum Problem: Error, CustomStringConvertible {
        case unknownVersion(Int)

        public var description: String {
            switch self {
            case .unknownVersion(let v): "capture set version \(v); this app reads version \(CaptureSet.version)"
            }
        }
    }

    public var version = CaptureSet.version
    public var created: Date
    public var mode: Mode
    public var seconds: Double
    public var phrase = CaptureSet.phrase
    public var commit: String?
    public var streams: [Stream] = []

    public init(created: Date, mode: Mode, seconds: Double) {
        self.created = created
        self.mode = mode
        self.seconds = seconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == Self.version else { throw Problem.unknownVersion(version) }
        created = try c.decode(Date.self, forKey: .created)
        mode = try c.decode(Mode.self, forKey: .mode)
        seconds = try c.decode(Double.self, forKey: .seconds)
        phrase = try c.decodeIfPresent(String.self, forKey: .phrase) ?? Self.phrase
        commit = try c.decodeIfPresent(String.self, forKey: .commit)
        streams = try c.decodeIfPresent([Stream].self, forKey: .streams) ?? []
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> CaptureSet {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CaptureSet.self, from: data)
    }

    /// Each stream's start (its newest buffer's host time less its length), as seconds after the earliest.
    public static func offsets(ends: [Double], lengths: [Double]) -> [Double] {
        let starts = zip(ends, lengths).map { $0 - $1 }
        guard let first = starts.min() else { return [] }
        return starts.map { $0 - first }
    }

    /// "2-usbaudio1-0": the row number and the mic's name, lower case, runs of anything else as one dash.
    public static func fileStem(index: Int, name: String) -> String {
        var slug = ""
        for ch in name.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                slug.append(ch)
            } else if !slug.isEmpty && slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.last == "-" { slug.removeLast() }
        return "\(index)-\(slug.isEmpty ? "mic" : slug)"
    }

    /// Best first by score; streams without a score (failed) last, in their own order.
    public static func ranked(_ streams: [Stream], scores: [Int: Int]) -> [Stream] {
        streams.enumerated().sorted { a, b in
            switch (scores[a.element.index], scores[b.element.index]) {
            case (let x?, let y?): x != y ? x > y : a.offset < b.offset
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }
}
