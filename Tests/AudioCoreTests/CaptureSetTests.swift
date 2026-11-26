import Foundation
import Testing

@testable import AudioCore

// Stories 017-019: capture sets and the mic score (docs/specs/2026-11-26-compare-mics.md).

private func sine(_ amp: Float, _ hz: Float, _ n: Int, _ rate: Float, from: Int = 0) -> [Float] {
    (0..<n).map { amp * sin(2 * .pi * hz * Float($0 + from) / rate) }
}

/// A second loud, a second quiet, and so on: speech and its pauses.
private func speech(rate: Float, seconds: Int) -> [Float] {
    var out: [Float] = []
    for s in 0..<seconds { out += sine(s % 2 == 0 ? 0.3 : 0.001, 440, Int(rate), rate, from: out.count) }
    return out
}

private struct Vector {
    let name: String
    let samples: [Float]
    let rate: Double
    let pieces: Int, floorDB: Double?, speechDB: Double?, snrDB: Double?, peakDB: Double
    let clips: Int, dropouts: Int, score: Int
}

/// Produced by context-grabber's own `MicSound` (native/ContextCore/Sources/ContextCore/Call/MicSound.swift, one
/// window: `add` the whole take, then `closeWindow`) on these same signals, 2026-11-26. The port must match it.
private let grabberVectors: [Vector] = [
    Vector(
        name: "speech48k", samples: speech(rate: 48000, seconds: 10), rate: 48000, pieces: 100, floorDB: -63.0103,
        speechDB: -13.4679, snrDB: 49.5425, peakDB: -10.4576, clips: 0, dropouts: 0, score: 100),
    Vector(
        name: "speech16k", samples: speech(rate: 16000, seconds: 6), rate: 16000, pieces: 60, floorDB: -63.0103,
        speechDB: -13.4679, snrDB: 49.5425, peakDB: -10.4576, clips: 0, dropouts: 0, score: 100),
    Vector(
        name: "clipped",
        samples: sine(1.2, 300, 48000 * 4, 48000).map { min(1, max(-1, $0)) } + sine(0.002, 300, 48000 * 4, 48000),
        rate: 48000, pieces: 80, floorDB: -56.9897, speechDB: -2.1232, snrDB: 54.8665, peakDB: 0, clips: 40,
        dropouts: 0, score: 83),
    Vector(
        name: "hiss", samples: sine(0.01, 1000, 48000 * 5, 48000), rate: 48000, pieces: 50, floorDB: -43.0103,
        speechDB: nil, snrDB: nil, peakDB: -40, clips: 0, dropouts: 0, score: 77),
    Vector(
        name: "dropouts", samples: [Float](repeating: 0, count: 24000 * 3) + speech(rate: 24000, seconds: 4),
        rate: 24000, pieces: 70, floorDB: -63.0103, speechDB: -13.4679, snrDB: 49.5424, peakDB: -10.4576, clips: 0,
        dropouts: 30, score: 49),
    Vector(
        name: "zeros", samples: [Float](repeating: 0, count: 48000 * 2), rate: 48000, pieces: 20, floorDB: nil,
        speechDB: nil, snrDB: nil, peakDB: -200, clips: 0, dropouts: 20, score: 0),
]

private func close(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case (let a?, let b?): abs(a - b) < 0.001
    default: false
    }
}

@Test(arguments: grabberVectors.map(\.name))
func micScoreMatchesGrabber(_ name: String) throws {
    let v = try #require(grabberVectors.first { $0.name == name })
    let r = MicScore.measure(v.samples, sampleRate: v.rate)
    #expect(r.pieces == v.pieces)
    #expect(close(r.floorDB, v.floorDB), "floor \(String(describing: r.floorDB))")
    #expect(close(r.speechDB, v.speechDB), "speech \(String(describing: r.speechDB))")
    #expect(close(r.snrDB, v.snrDB), "snr \(String(describing: r.snrDB))")
    #expect(close(r.peakDB, v.peakDB), "peak \(r.peakDB)")
    #expect(r.clips == v.clips)
    #expect(r.dropouts == v.dropouts)
    #expect(r.score == v.score)
}

@Test func micScoreRanksBestFirstAndFailuresLast() {
    let good = CaptureSet.Stream(index: 1, name: "USB", uid: "u", kind: .usb, rate: 48000, file: "1-usb.wav")
    let bad = CaptureSet.Stream(index: 2, name: "Built-in", uid: "b", kind: .builtIn, rate: 48000, file: "2-b.wav")
    let failed = CaptureSet.Stream(index: 3, name: "iPhone", uid: "i", kind: .continuity, error: "would not open")
    let scores = [1: 90, 2: 40]
    #expect(CaptureSet.ranked([failed, bad, good], scores: scores).map(\.index) == [1, 2, 3])
}

@Test func captureSetRoundTrips() throws {
    var set = CaptureSet(created: Date(timeIntervalSince1970: 1_795_725_525), mode: .together, seconds: 10)
    set.commit = "da3bfb9"
    set.streams = [
        .init(
            index: 1, name: "MacBook Pro Microphone", uid: "BuiltInMicrophoneDevice", kind: .builtIn, rate: 48000,
            file: "1-macbook-pro-microphone.wav", offset: 0.012, started: 100.25, openMs: 126),
        .init(index: 2, name: "Work iPhone", uid: "x", kind: .continuity, openMs: 3010, error: "unplugged"),
    ]
    let data = try set.encoded()
    let back = try CaptureSet.decode(data)
    #expect(back == set)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"version\" : 1"))
    #expect(json.contains("\"mode\" : \"together\""))
}

@Test func captureSetRejectsAnUnknownVersion() {
    let json = Data(#"{"version": 2, "created": "2026-11-26T20:40:38Z", "mode": "together", "seconds": 10}"#.utf8)
    #expect(throws: CaptureSet.Problem.self) { try CaptureSet.decode(json) }
}

@Test func offsetsAreFromTheEarliestStart() {
    // Each stream: the host time of its newest buffer and its length; start = end - length.
    let offsets = CaptureSet.offsets(ends: [10.020, 10.005, 10.050], lengths: [10, 10, 10.03])
    #expect(offsets.map { ($0 * 1000).rounded() } == [15, 0, 15])
}

@Test func streamFileNamesAreSlugs() {
    #expect(CaptureSet.fileStem(index: 2, name: "USBAudio1.0") == "2-usbaudio1-0")
    #expect(CaptureSet.fileStem(index: 1, name: "MacBook Pro Microphone") == "1-macbook-pro-microphone")
}

@Test func togetherSkipsBluetoothAndContinuity() {
    let mics = [
        Mic(uid: "a", name: "AirPods", kind: .bluetooth), Mic(uid: "b", name: "MacBook", kind: .builtIn),
        Mic(uid: "c", name: "iPhone", kind: .continuity), Mic(uid: "d", name: "USB", kind: .usb),
    ]
    #expect(CaptureSet.Mode.together.mics(from: mics).map(\.uid) == ["b", "d"])
    #expect(CaptureSet.Mode.inTurn.mics(from: mics).map(\.uid) == ["a", "b", "c", "d"])
    #expect(CaptureSet.Mode.together.mics(from: mics, matching: "mac").map(\.uid) == ["b"])
}

@Test func chooseNeverPicksAContinuityMicFirst() {
    let mics = [Mic(uid: "c", name: "iPhone", kind: .continuity), Mic(uid: "b", name: "MacBook", kind: .builtIn)]
    #expect(Mic.choose(from: mics, wanted: nil)?.uid == "b")
}
