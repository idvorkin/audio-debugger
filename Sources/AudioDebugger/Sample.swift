import AudioCore
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Story 013: S saves the last 20 s the mic heard, raw, as `samples/<yyyyMMdd-HHmmss>/sample.wav` under
/// `SessionLog.root` (outside `bugs/`, so the bug-kit listener never files it), with `sample.json` beside it: the
/// mic and the clip's measured noise floor, speech level and separation (AudioCore/NoiseMetrics.swift).
extension AppModel {
    func saveSample() {
        let (audio, rate) = capture.last(seconds: replaySeconds)
        guard !audio.isEmpty else {
            Log.app.info("save sample: nothing captured yet")
            return
        }
        let name = Self.sampleStamp.string(from: Date())
        let folder = SessionLog.root.appendingPathComponent("samples/\(name)", isDirectory: true)
        let micName = mic?.name ?? "none", commit = Self.buildCommit
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let wav = folder.appendingPathComponent("sample.wav")
                try writeWAV(audio, sampleRate: rate, to: wav)
                let sidecar = sampleSidecar(audio, rate: rate, mic: micName, commit: commit)
                let json = try JSONSerialization.data(withJSONObject: sidecar, options: [.prettyPrinted, .sortedKeys])
                try json.write(to: folder.appendingPathComponent("sample.json"))
                await MainActor.run {
                    SessionLog.shared.event("sample_saved", sidecar.merging(["folder": name]) { a, _ in a })
                    Log.app.info("saved sample samples/\(name, privacy: .public)")
                    self.sampleSaved = name
                    #if os(macOS)
                    if !Launch.scripted { NSWorkspace.shared.activateFileViewerSelecting([wav]) }
                    #endif
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        MainActor.assumeIsolated { if self.sampleSaved == name { self.sampleSaved = nil } }
                    }
                }
            } catch {
                await MainActor.run {
                    Log.app.error("save sample failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// H: what the noise readout means (docs/noise.html). The Mac app bundles the page (`just app`), so it opens
    /// offline; elsewhere the published copy.
    func openNoiseGuide() {
        guard let url = Bundle.main.url(forResource: "noise", withExtension: "html") ?? URL(string: Self.noiseGuideWeb)
        else { return }
        SessionLog.shared.event("noise_guide", ["url": url.absoluteString])
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    // ponytail: the iPhone has no bundled copy and the repo has no GitHub Pages yet, so this link 404s until Pages
    // serves docs/ from main; the upgrade is bundling the page in the iOS app and showing it in a web view.
    static let noiseGuideWeb = "https://idvorkin.github.io/audio-debugger/noise.html"

    private static let sampleStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

/// A saved sample's sidecar: numbers stay numbers, so `jq` compares them.
func sampleSidecar(_ x: [Float], rate: Double, mic: String, commit: String) -> [String: Any] {
    var d: [String: Any] = [
        "mic": mic, "sample_rate": rate, "seconds": jsonNumber(Double(x.count) / rate, places: 2), "commit": commit,
        "saved_at": ISO8601DateFormatter().string(from: Date()), "audio": "raw (no noise reduction or boost)",
        "peak_db": tenths(decibels(peak(x[...]))), "clipped_samples": clippedSamples(x),
        "method":
            "RMS of 50 ms frames; floor = 10th percentile, median = 50th, speech = 95th; separation = speech - floor",
    ]
    if let s = LevelSummary(levelsDB: frameLevelsDB(x, sampleRate: rate)) {
        d["noise_floor_db"] = tenths(s.floorDB)
        d["median_db"] = tenths(s.medianDB)
        d["speech_db"] = tenths(s.speechDB)
        d["separation_db"] = tenths(s.separationDB)
        d["separation"] = s.separation.rawValue
    }
    return d
}

private func tenths(_ db: Float) -> NSDecimalNumber { jsonNumber(Double(db), places: 1) }
