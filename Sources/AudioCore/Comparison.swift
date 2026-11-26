import Foundation

/// Story 019: a capture set loaded for comparison, from its files alone: each stream's samples, its score (`MicScore`,
/// recomputed from the WAV, so an old set scores as a new one), its long-term spectrum and bandwidth, ranked best to
/// worst. Spec: docs/specs/2026-11-26-compare-mics.md.
public struct Comparison: Sendable {
    public struct Row: Sendable {
        public let stream: CaptureSet.Stream
        public let samples: [Float]
        public let rate: Double
        public let reading: MicScore.Reading?
        /// The long-term average spectrum, log-spaced from 40 Hz to the mic's Nyquist: (Hz, dBFS).
        public let spectrum: [SpectrumPoint]
        /// Why the stream has no audio: the manifest's error, or the WAV failing to load.
        public let problem: String?
        /// 600 min/max buckets of the samples, and their peak: worked out once, for drawing.
        public let envelope: [(min: Float, max: Float)]
        public let peak: Float

        public init(
            stream: CaptureSet.Stream, samples: [Float], rate: Double, reading: MicScore.Reading?,
            spectrum: [SpectrumPoint], problem: String?
        ) {
            self.stream = stream
            self.samples = samples
            self.rate = rate
            self.reading = reading
            self.spectrum = spectrum
            self.problem = problem
            envelope = AudioCore.envelope(samples, buckets: 600)
            peak = AudioCore.peak(samples[...])
        }

        public var seconds: Double { rate > 0 ? Double(samples.count) / rate : 0 }
        public var offset: Double { stream.offset ?? 0 }
        /// The highest frequency the rate can carry; under 8 kHz a voice loses its consonants (story 015's mark).
        public var nyquist: Double? { stream.rate.map { $0 / 2 } }
    }

    public struct SpectrumPoint: Sendable, Equatable {
        public let hz: Float
        public let db: Float
    }

    public let set: CaptureSet
    /// Best first; rows without audio last.
    public let rows: [Row]

    /// The set's span: from the earliest start to the latest end.
    public var span: Double { rows.map { $0.offset + $0.seconds }.max() ?? 0 }

    public init(set: CaptureSet, rows: [Row]) {
        self.set = set
        let scores = Dictionary(
            uniqueKeysWithValues: rows.compactMap { r in r.reading.map { (r.stream.index, $0.score) } })
        let order = CaptureSet.ranked(rows.map(\.stream), scores: scores).map(\.index)
        self.rows = order.compactMap { index in rows.first { $0.stream.index == index } }
    }

    /// Reads `manifest.json` and every stream's WAV in `folder`.
    public static func load(_ folder: URL) throws -> Comparison {
        let set = try CaptureSet.decode(Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        let rows = set.streams.map { stream -> Row in
            guard stream.error == nil, let file = stream.file else {
                return Row(
                    stream: stream, samples: [], rate: 0, reading: nil, spectrum: [],
                    problem: stream.error ?? "no file")
            }
            do {
                let wav = try WAV.decode(Data(contentsOf: folder.appendingPathComponent(file)))
                return Row(
                    stream: stream, samples: wav.samples, rate: wav.rate,
                    reading: MicScore.measure(wav.samples, sampleRate: wav.rate),
                    spectrum: averageSpectrum(wav.samples, rate: wav.rate), problem: nil)
            } catch {
                return Row(
                    stream: stream, samples: [], rate: 0, reading: nil, spectrum: [],
                    problem: "\(file): \(error)")
            }
        }
        return Comparison(set: set, rows: rows)
    }

    /// A/B: the place in `to` that was heard at `seconds` into `from`, on the set's shared timeline (each stream has
    /// its own rate and start), clamped to `to`'s length.
    public static func position(_ seconds: Double, from: Row, to: Row) -> Double {
        min(max(0, seconds + from.offset - to.offset), to.seconds)
    }

    /// Power-averaged Hann spectra of 4096-sample frames, reduced to `points` log-spaced bands (each the band's mean
    /// power) from 40 Hz to Nyquist.
    public static func averageSpectrum(_ x: [Float], rate: Double, points: Int = 160) -> [SpectrumPoint] {
        let size = 4096
        guard x.count >= size, rate > 0 else { return [] }
        let analyzer = SpectrumAnalyzer(size: size, sampleRate: rate)
        var power = [Double](repeating: 0, count: size / 2 - 1)
        var frames = 0
        var start = 0
        while start + size <= x.count {
            let db = analyzer.decibelSpectrum(Array(x[start..<(start + size)]))
            for (k, d) in db.enumerated() { power[k] += pow(10, Double(d) / 10) }
            frames += 1
            start += size
        }
        let freqs = analyzer.frequencies
        let lo = log10(40.0), hi = log10(rate / 2)
        var out: [SpectrumPoint] = []
        for p in 0..<points {
            let a = pow(10, lo + (hi - lo) * Double(p) / Double(points))
            let b = pow(10, lo + (hi - lo) * Double(p + 1) / Double(points))
            var sum = 0.0, n = 0
            for (k, f) in freqs.enumerated() where Double(f) >= a && Double(f) < b {
                sum += power[k]
                n += 1
            }
            guard n > 0 else { continue }
            let mean = sum / Double(n) / Double(frames)
            out.append(SpectrumPoint(hz: Float((a * b).squareRoot()), db: Float(10 * log10(max(mean, 1e-20)))))
        }
        return out
    }
}
