import Accelerate

/// Decibels relative to full scale; silence floors at -200 dB instead of -infinity.
public func decibels(_ amplitude: Float) -> Float { 20 * log10(max(amplitude, 1e-10)) }

public func rms(_ x: ArraySlice<Float>) -> Float {
    x.isEmpty ? 0 : x.withUnsafeBufferPointer { vDSP.rootMeanSquare($0) }
}

public func peak(_ x: ArraySlice<Float>) -> Float {
    x.isEmpty ? 0 : x.withUnsafeBufferPointer { vDSP.maximumMagnitude($0) }
}

/// What the meter says about the input gain, from the current peak and the held peak.
public enum GainHint: String, Sendable {
    case tooQuiet = "too quiet — turn gain up"
    case good = "good level"
    case hot = "hot — back off gain"

    public init(peakDB: Float, heldPeakDB: Float) {
        if heldPeakDB > -3 {
            self = .hot
        } else if peakDB < -30 {
            self = .tooQuiet
        } else {
            self = .good
        }
    }
}

/// The noise floor: the 10th percentile of the RMS readings over the last `window` of them (5 s at 30 Hz), ignoring
/// digital silence. A running minimum latched onto the near-silent buffers a mic sends while it starts (-110 dB on
/// a mic whose room floor is -45).
public struct NoiseFloor: Sendable {
    public let window: Int
    private var readings: [Float] = []
    public private(set) var db: Float?

    public init(window: Int = 150) { self.window = window }

    public mutating func update(rmsDB: Float) {
        guard rmsDB > -150 else { return }  // digital silence: no signal, not a quiet room
        readings.append(rmsDB)
        if readings.count > window { readings.removeFirst(readings.count - window) }
        db = readings.sorted()[readings.count / 10]
    }
}

/// Music-note name for a frequency, e.g. "A4 +0¢"; "—" when there is no pitch.
public func noteName(_ freq: Float) -> String {
    guard freq > 0 else { return "—" }
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let midi = 69 + 12 * log2(freq / 440)
    let n = Int(midi.rounded())
    let cents = Int(((midi - Float(n)) * 100).rounded())
    let octave = Int((Double(n) / 12).rounded(.down)) - 1
    return "\(names[((n % 12) + 12) % 12])\(octave) \(cents >= 0 ? "+" : "")\(cents)¢"
}
