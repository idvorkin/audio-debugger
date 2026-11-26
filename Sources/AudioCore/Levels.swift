import Accelerate

// `decibels`, the noise floor and the speech level are in NoiseMetrics.swift.

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
