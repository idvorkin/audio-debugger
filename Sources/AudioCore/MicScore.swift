import Foundation

/// Stories 017-019: how a mic sounded over one take, scored 0-100. A port of context-grabber's `MicSound`
/// (native/ContextCore/Sources/ContextCore/Call/MicSound.swift), exactly, with a whole take as its one window: every
/// tenth of a second is a piece (its RMS and peak, whether it clipped, whether it was digital silence); the floor is the
/// quiet pieces' level (10th percentile), speech the loud ones' (90th), counted only 6 dB over the floor. The host test
/// pins it with vectors from Grabber's own function. Plain loops, no Accelerate, like NoiseMetrics.
///
/// Its floor is the **score floor** (100 ms pieces over the take), not the live readout's noise floor (50 ms frames
/// over 20 s): the two are shown under different names.
public enum MicScore {
    public struct Reading: Equatable, Sendable {
        public var pieces = 0
        public var floorDB: Double?
        public var speechDB: Double?
        public var snrDB: Double?
        public var peakDB: Double = MicScore.silenceDB
        public var clips = 0
        public var dropouts = 0
        public var score = 0
        public var speech: Bool { snrDB != nil }
    }

    public static let silenceDB = -200.0
    /// Full scale, near enough: a piece whose loudest sample reaches this clipped.
    static let clipLevel: Float = 0.999
    /// Speech less than this far over the floor is no speech.
    static let speechOverFloorDB = 6.0

    public static func measure(_ samples: [Float], sampleRate: Double) -> Reading {
        let size = max(1, Int((sampleRate / 10).rounded()))
        var reading = Reading()
        var levels: [Double] = []
        var peak: Float = 0
        var start = 0
        while samples.count - start >= size {
            var sum: Double = 0
            var loudest: Float = 0
            for sample in samples[start..<(start + size)] {
                sum += Double(sample) * Double(sample)
                loudest = max(loudest, abs(sample))
            }
            start += size
            reading.pieces += 1
            peak = max(peak, loudest)
            if loudest == 0 {
                reading.dropouts += 1
                continue
            }
            if loudest >= clipLevel { reading.clips += 1 }
            levels.append(decibels((sum / Double(size)).squareRoot()))
        }
        reading.peakDB = decibels(Double(peak))
        if !levels.isEmpty {
            let sorted = levels.sorted()
            let floor = sorted[sorted.count / 10]
            let loud = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
            reading.floorDB = floor
            if loud - floor >= speechOverFloorDB {
                reading.speechDB = loud
                reading.snrDB = loud - floor
            }
        }
        if reading.pieces > 0 {
            reading.score = score(
                snrDB: reading.snrDB, floorDB: reading.floorDB,
                clipFraction: Double(reading.clips) / Double(reading.pieces),
                dropoutFraction: Double(reading.dropouts) / Double(reading.pieces))
        }
        return reading
    }

    /// SNR 50 points (30 dB full, 0 dB none), floor 20 (-60 dBFS full, -30 none), clipping 15 (none full, 10% of
    /// pieces none), dropouts 15 (none full, 20% none); each linear. SNR, floor and clipping are earned only by the
    /// pieces with sound, so a mic of digital silence scores 0. No speech: the other three, scaled to 100.
    public static func score(snrDB: Double?, floorDB: Double?, clipFraction: Double, dropoutFraction: Double) -> Int {
        func part(_ points: Double, _ value: Double, full: Double, zero: Double) -> Double {
            let t = (value - zero) / (full - zero)
            return points * min(1, max(0, t))
        }
        let sound = 1 - min(1, max(0, dropoutFraction))
        let floor = floorDB.map { part(20, $0, full: -60, zero: -30) } ?? 0
        let clipping = part(15, clipFraction, full: 0, zero: 0.1)
        let dropouts = part(15, dropoutFraction, full: 0, zero: 0.2)
        guard let snrDB else { return Int((((floor + clipping) * sound + dropouts) * 2).rounded()) }
        return Int(((part(50, snrDB, full: 30, zero: 0) + floor + clipping) * sound + dropouts).rounded())
    }

    static func decibels(_ amplitude: Double) -> Double { amplitude > 0 ? 20 * log10(amplitude) : silenceDB }
}
