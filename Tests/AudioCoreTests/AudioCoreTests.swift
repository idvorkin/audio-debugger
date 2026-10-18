import Foundation
import Testing

@testable import AudioCore

private func sine(_ freq: Float, amplitude: Float = 1, count: Int, rate: Float = 48_000) -> [Float] {
    (0..<count).map { amplitude * sin(2 * .pi * freq * Float($0) / rate) }
}

/// Deterministic white-ish noise (no RNG state to share between tests).
private func noise(_ count: Int, amplitude: Float, seed: UInt64 = 1) -> [Float] {
    var s = seed
    return (0..<count).map { _ in
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return amplitude * (Float(s >> 40) / Float(1 << 24) * 2 - 1)
    }
}

// MARK: Levels

@Test func levelsOfAFullScaleSine() {
    let x = sine(1000, count: 48_000)
    #expect(abs(decibels(rms(x[...])) - -3.01) < 0.05)
    #expect(abs(decibels(peak(x[...]))) < 0.01)
    #expect(decibels(0) == -200)
}

@Test func gainHintReadsQuietGoodAndHot() {
    #expect(GainHint(peakDB: -40, heldPeakDB: -35) == .tooQuiet)
    #expect(GainHint(peakDB: -12, heldPeakDB: -10) == .good)
    #expect(GainHint(peakDB: -12, heldPeakDB: -1) == .hot)
}

// Speech over a -45 dB room: the floor reads the room, not the speech, and not a start-up glitch.
@Test func noiseFloorReadsTheRoom() {
    var f = NoiseFloor(window: 100)
    f.update(rmsDB: -200)  // digital silence while the mic starts: ignored
    #expect(f.db == nil)
    f.update(rmsDB: -110)  // one near-silent start-up buffer
    for k in 0..<100 { f.update(rmsDB: k % 3 == 0 ? -45 : -25) }  // a third of the time between words
    #expect(f.db == -45)
}

@Test func noiseFloorForgetsOldReadings() {
    var f = NoiseFloor(window: 10)
    for _ in 0..<10 { f.update(rmsDB: -60) }
    #expect(f.db == -60)
    for _ in 0..<10 { f.update(rmsDB: -40) }  // the room got louder
    #expect(f.db == -40)
}

@Test func noteNames() {
    #expect(noteName(440) == "A4 +0¢")
    #expect(noteName(261.63) == "C4 +0¢")
    #expect(noteName(0) == "—")
}

// MARK: FFT and spectrum

@Test func fftRoundTrips() {
    let fft = RealFFT(n: 1024)
    let x = noise(1024, amplitude: 0.5)
    let (re, im) = fft.forward(x)
    let y = fft.inverse(real: re, imag: im)
    #expect(zip(x, y).allSatisfy { abs($0 - $1) < 1e-4 })
}

// A sine centred on a bin reads its amplitude in dBFS: 0.5 → -6 dB, at the right frequency.
@Test func spectrumIsCalibratedInDBFS() {
    let a = SpectrumAnalyzer(size: 4096, sampleRate: 48_000)
    let freq = Float(100 * 48_000) / 4096  // bin 100
    let db = a.decibelSpectrum(sine(freq, amplitude: 0.5, count: 4096))
    let k = db.indices.max { db[$0] < db[$1] } ?? 0
    #expect(abs(a.frequencies[k] - freq) < 1)
    #expect(abs(db[k] - -6.02) < 0.1)
}

// MARK: Pitch

@Test(arguments: [60, 80, 100, 220, 440, 900] as [Float])
func pitchOfQuietSines(freq: Float) {
    let p = PitchDetector(size: 4096, sampleRate: 48_000)
    let got = p.pitch(sine(freq, amplitude: 0.003, count: 4096))
    #expect(abs(got - freq) / freq < 0.015)
}

@Test func pitchOfSilenceAndNoiseIsNone() {
    let p = PitchDetector(size: 4096, sampleRate: 48_000)
    #expect(p.pitch([Float](repeating: 0, count: 4096)) == 0)
    #expect(p.pitch(noise(4096, amplitude: 0.1)) == 0)
}

// MARK: Replay ring and transport

@Test func ringKeepsTheNewestInOrderAcrossWraps() {
    var r = RingBuffer(capacity: 1000)
    #expect(r.last(10).isEmpty)
    let ramp = (0..<3333).map(Float.init)
    for chunk in stride(from: 0, to: ramp.count, by: 512) {
        r.write(Array(ramp[chunk..<min(chunk + 512, ramp.count)]))
        let n = min(r.total, 1000)
        #expect(r.last(5000) == Array(ramp[(min(chunk + 512, ramp.count) - n)..<min(chunk + 512, ramp.count)]))
    }
    #expect(r.last(3) == [3330, 3331, 3332])
}

@Test func transportPausesSeeksAndStopsAtTheEnd() {
    var t = Transport(length: 1000)
    #expect(t.advance(frames: 256).isEmpty)  // paused until played
    t.play()
    #expect(t.advance(frames: 600) == 0..<600)
    t.pause()
    #expect(t.advance(frames: 100).isEmpty)
    t.seek(to: 900)
    t.play()
    #expect(t.advance(frames: 600) == 900..<1000)
    #expect(!t.playing && t.atEnd)
    t.togglePlay()  // play from the end starts over
    #expect(t.position == 0 && t.playing)
    t.seek(to: 5000)
    #expect(t.position == 1000)
    t.load(length: 400)
    #expect(t.position == 400)
}

// MARK: Processing

// A voice-like signal (harmonics, on half the time) under hiss. Denoise and boost each widen the gap between the
// voiced and silent halves; together by more than 15 dB over plain normalisation.
@Test func denoiseAndBoostRaiseVoiceOverHiss() {
    let rate: Float = 48_000
    let n = 4 * 48_000
    let on = (0..<n).map { sin(2 * Float.pi * 0.5 * Float($0) / rate) > 0 }
    var voice = [Float](repeating: 0, count: n)
    for k in 1...7 {
        let h = sine(150 * Float(k), amplitude: 0.003 / Float(k), count: n)
        for i in 0..<n where on[i] { voice[i] += h[i] }
    }
    let x = zip(voice, noise(n, amplitude: 0.0035)).map { $0 + $1 }
    func snr(_ y: [Float]) -> Float {
        let v = y.indices.filter { on[$0] }.map { y[$0] * y[$0] }
        let s = y.indices.filter { !on[$0] }.map { y[$0] * y[$0] }
        return 10 * log10((v.reduce(0, +) / Float(v.count)) / (s.reduce(0, +) / Float(s.count)))
    }
    let plain = snr(normalizePeak(x))
    let cleaned = voiceBoost(denoise(x), sampleRate: rate)
    #expect(cleaned.count == x.count)
    #expect(snr(denoise(x)) > plain + 8)
    #expect(snr(cleaned) > plain + 15)
    #expect(peak(cleaned[...]) <= 1)
}

@Test func voiceBoostBringsQuietSpeechToTarget() {
    let y = voiceBoost(sine(300, amplitude: 0.003, count: 48_000), sampleRate: 48_000)
    #expect(abs(decibels(rms(y[24_000...])) - -16) < 1.5)
}

// One second of speech in twenty of hiss (Codex review): the speech, not the hiss, is brought to the target.
@Test func voiceBoostLevelsBriefSpeechNotTheBackground() {
    let rate: Float = 48_000
    var x = noise(20 * 48_000, amplitude: 0.002)
    let speech = sine(300, amplitude: 0.02, count: 48_000)
    for i in 0..<48_000 { x[5 * 48_000 + i] += speech[i] }
    let y = voiceBoost(x, sampleRate: rate)
    let speechDB = decibels(rms(y[(5 * 48_000 + 4_800)..<(6 * 48_000 - 4_800)]))
    let hissDB = decibels(rms(y[(10 * 48_000)...]))
    #expect(abs(speechDB - -16) < 2)
    #expect(speechDB - hissDB > 15)
}

// Recorded digital silence (a dropout) must not become the noise profile and let the hiss through.
@Test func denoiseIgnoresDigitalSilenceInTheProfile() {
    var x = noise(4 * 48_000, amplitude: 0.003)
    for i in 0..<(48_000) { x[i] = 0 }  // the first second is a dropout
    let y = denoise(x)
    #expect(decibels(rms(y[(2 * 48_000)...])) < decibels(rms(x[(2 * 48_000)...])) - 10)
}

@Test func voiceBoostCutsRumble() {
    let mix = zip(sine(30, amplitude: 0.1, count: 48_000), sine(300, amplitude: 0.1, count: 48_000)).map { $0 + $1 }
    let y = voiceBoost(mix, sampleRate: 48_000)
    let a = SpectrumAnalyzer(size: 4096, sampleRate: 48_000)
    let db = a.decibelSpectrum(Array(y[40_000..<44_096]))
    let bin = { (f: Float) in a.frequencies.indices.min { abs(a.frequencies[$0] - f) < abs(a.frequencies[$1] - f) } ?? 0
    }
    #expect(db[bin(300)] - db[bin(30)] > 20)
}

@Test func normalizePeakAndEnvelope() {
    let y = normalizePeak([0, 0.1, -0.2])
    #expect(abs(peak(y[...]) - 0.89) < 1e-6)
    #expect(normalizePeak([0, 0]) == [0, 0])
    let e = envelope([1, -1, 2, -2, 3, -3], buckets: 3)
    #expect(e.map(\.min) == [-1, -2, -3] && e.map(\.max) == [1, 2, 3])
}

// MARK: Spectrogram

@Test func spectrogramScrollsLeftWithLowFrequenciesAtTheBottom() {
    var s = Spectrogram(width: 4, height: 2)
    s.push([-20, -100])  // loud low bin, quiet high bin
    #expect(s.pixels[1 * 4 + 3] == Spectrogram.lut[255])  // bottom row, newest column
    #expect(s.pixels[0 * 4 + 3] == Spectrogram.lut[0])
    s.push([-100, -100])
    #expect(s.pixels[1 * 4 + 2] == Spectrogram.lut[255])  // moved one column left
}
