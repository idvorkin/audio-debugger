import Foundation
import Testing

@testable import AudioCore

// Story 019: a capture set loads from its files, scores and ranks its mics, and lines them up.

private func sine(_ amp: Float, _ hz: Float, _ n: Int, _ rate: Float) -> [Float] {
    (0..<n).map { amp * sin(2 * .pi * hz * Float($0) / rate) }
}

/// Speech-like: a loud second, a quiet one.
private func talk(_ loud: Float, quiet: Float, rate: Float, seconds: Int) -> [Float] {
    (0..<seconds).flatMap { s in sine(s % 2 == 0 ? loud : quiet, 440, Int(rate), rate) }
}

@Test func wavRoundTrips() throws {
    let x: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
    let back = try WAV.decode(WAV.encode(x, rate: 44100))
    #expect(back.samples == x)
    #expect(back.rate == 44100)
}

@Test func wavReadsSixteenBitPCM() throws {
    var d = Data("RIFF".utf8)
    d.append(contentsOf: [40, 0, 0, 0])
    d.append(contentsOf: Array("WAVEfmt ".utf8))
    d.append(contentsOf: [16, 0, 0, 0, 1, 0, 1, 0, 0x80, 0x3E, 0, 0, 0, 0x7D, 0, 0, 2, 0, 16, 0])  // 16 kHz
    d.append(contentsOf: Array("data".utf8))
    d.append(contentsOf: [4, 0, 0, 0, 0x00, 0x40, 0x00, 0xC0])  // 0.5, -0.5
    let w = try WAV.decode(d)
    #expect(w.rate == 16000)
    #expect(w.samples == [0.5, -0.5])
}

@Test func wavRejectsJunk() {
    #expect(throws: WAV.Problem.notWAV) { try WAV.decode(Data("hello world!".utf8)) }
}

@Test func wavTruncatedAnywhereThrowsNeverTraps() {
    let whole = WAV.encode([0.1, 0.2, 0.3], rate: 48000)
    for cut in 0..<(whole.count - 12) {
        _ = try? WAV.decode(whole.prefix(cut))  // must return or throw for every prefix
    }
}

/// Three mics and a failure, written to a temp folder as the app writes a set: the loader must rank them by score
/// from the WAVs alone, keep the failure last, and carry each stream's offset.
@Test func comparisonLoadsRanksAndAligns() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let clean = talk(0.3, quiet: 0.0005, rate: 48000, seconds: 4)  // deep floor, high SNR
    let noisy = talk(0.3, quiet: 0.05, rate: 48000, seconds: 4)  // floor 15 dB under speech
    let narrow = talk(0.3, quiet: 0.005, rate: 16000, seconds: 4)  // a headset's rate
    var set = CaptureSet(created: Date(timeIntervalSince1970: 0), mode: .together, seconds: 4)
    set.streams = [
        .init(index: 1, name: "Noisy", uid: "n", kind: .usb, rate: 48000, file: "1-noisy.wav", offset: 0.02),
        .init(index: 2, name: "iPhone", uid: "i", kind: .continuity, error: "would not open"),
        .init(index: 3, name: "Clean", uid: "c", kind: .builtIn, rate: 48000, file: "3-clean.wav", offset: 0),
        .init(index: 4, name: "Headset", uid: "h", kind: .bluetooth, rate: 16000, file: "4-headset.wav", offset: 0.01),
    ]
    try WAV.encode(noisy, rate: 48000).write(to: folder.appendingPathComponent("1-noisy.wav"))
    try WAV.encode(clean, rate: 48000).write(to: folder.appendingPathComponent("3-clean.wav"))
    try WAV.encode(narrow, rate: 16000).write(to: folder.appendingPathComponent("4-headset.wav"))
    try set.encoded().write(to: folder.appendingPathComponent("manifest.json"))

    let c = try Comparison.load(folder)
    #expect(c.rows.map(\.stream.name) == ["Clean", "Headset", "Noisy", "iPhone"])
    let scores = c.rows.compactMap { $0.reading?.score }
    #expect(scores == scores.sorted(by: >))
    #expect(c.rows.last?.problem == "would not open")
    #expect(c.rows[1].nyquist == 8000)
    #expect(abs(c.span - 4.02) < 0.001)

    // A/B: 1 s into Noisy (which started 20 ms late) is 1.02 s into Clean, and 1.01 s into Headset.
    let noisyRow = try #require(c.rows.first { $0.stream.name == "Noisy" })
    #expect(abs(Comparison.position(1, from: noisyRow, to: c.rows[0]) - 1.02) < 1e-9)
    #expect(abs(Comparison.position(1, from: noisyRow, to: c.rows[1]) - 1.01) < 1e-9)
    #expect(Comparison.position(10, from: noisyRow, to: c.rows[0]) == 4)
}

@Test func averageSpectrumPeaksAtTheTone() throws {
    let s = Comparison.averageSpectrum(sine(0.5, 1000, 48000, 48000), rate: 48000)
    let top = try #require(s.max { $0.db < $1.db })
    #expect(abs(top.hz - 1000) < 100)
    #expect(s.last.map { $0.hz < 24000 } == true)
}
