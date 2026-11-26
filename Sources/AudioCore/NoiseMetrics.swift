import Foundation

// "How much background noise is there?" One definition for the live readout, a saved sample's sidecar and
// docs/noise.html: short RMS frames, the 10th percentile is the noise floor (the gaps between words), the 95th is the
// speech level, and the gap between them is the separation. Plain Swift, no Accelerate.

/// Decibels relative to full scale; silence floors at -200 dB instead of -infinity.
public func decibels(_ amplitude: Float) -> Float { 20 * log10(max(amplitude, 1e-10)) }

/// Readings at or below this are digital silence (a mic starting up, a muted input): no signal, not a quiet room.
public let digitalSilenceDB: Float = -150

/// The value at fraction `p` (0…1) of an ascending array.
func percentile(_ sorted: [Float], _ p: Float) -> Float {
    sorted[Int((Float(sorted.count - 1) * p).rounded())]
}

/// Speech level minus noise floor, read against a speech recognizer's needs. A rule of thumb, not a lab SNR: the
/// 95th percentile of short frames sits several dB above a speech average, so these bands read higher than the
/// SNR figures in ASR papers (docs/noise.html explains the gap).
public enum Separation: String, Sendable {
    /// Under `heardBelow`: the loud frames are barely above the quiet ones, so there is no speech to measure, or
    /// the noise is as loud as the voice. The meter cannot tell which; the replay can.
    case noSpeech = "no speech heard"
    case poor
    case ok
    case good

    public static let heardBelow: Float = 6
    public static let okFrom: Float = 15
    public static let goodFrom: Float = 30

    public init(db: Float) {
        if db < Self.heardBelow {
            self = .noSpeech
        } else if db < Self.okFrom {
            self = .poor
        } else if db < Self.goodFrom {
            self = .ok
        } else {
            self = .good
        }
    }
}

/// Floor, median and speech level of a run of frame levels (dBFS), and the separation between floor and speech.
public struct LevelSummary: Sendable, Equatable {
    public let floorDB: Float
    public let medianDB: Float
    public let speechDB: Float
    public var separationDB: Float { speechDB - floorDB }
    public var separation: Separation { Separation(db: separationDB) }

    /// Nil when every level is digital silence.
    public init?(levelsDB: [Float]) {
        let sorted = levelsDB.filter { $0 > digitalSilenceDB }.sorted()
        guard !sorted.isEmpty else { return nil }
        floorDB = percentile(sorted, 0.10)
        medianDB = percentile(sorted, 0.50)
        speechDB = percentile(sorted, 0.95)
    }
}

/// RMS level (dBFS) of each whole `frameSeconds` frame of a clip; a partial last frame is dropped.
public func frameLevelsDB(_ x: [Float], sampleRate: Double, frameSeconds: Double = 0.05) -> [Float] {
    let n = max(1, Int(sampleRate * frameSeconds))
    return stride(from: 0, through: x.count - n, by: n).map { start in
        var sum: Float = 0
        for v in x[start..<start + n] { sum += v * v }
        return decibels((sum / Float(n)).squareRoot())
    }
}

/// Samples at or past full scale (|x| ≥ 0.999), as the live clip counter counts them.
public func clippedSamples(_ x: [Float]) -> Int { x.reduce(0) { $0 + (abs($1) >= 0.999 ? 1 : 0) } }

/// The live noise floor and speech level: percentiles of the last `window` RMS readings (20 s at 30 Hz, the replay's
/// length, so the live readout and a saved sample measure the same span), ignoring digital silence. Percentiles,
/// not a running minimum, which latched onto the near-silent buffers a mic sends while it starts (-110 dB on a mic
/// whose room floor is -45).
public struct NoiseFloor: Sendable {
    public let window: Int
    private var readings: [Float] = []
    public private(set) var summary: LevelSummary?
    public var db: Float? { summary?.floorDB }

    public init(window: Int = 600) { self.window = window }

    public mutating func update(rmsDB: Float) {
        guard rmsDB > digitalSilenceDB else { return }
        readings.append(rmsDB)
        if readings.count > window { readings.removeFirst(readings.count - window) }
        summary = LevelSummary(levelsDB: readings)
    }
}
