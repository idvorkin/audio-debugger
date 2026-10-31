import AVFoundation
import AudioCore
import BugKit
import Foundation

/// ⌘I bug reports through BugKit (story 006): a folder `bugs/<yyyyMMdd-HHmmss>/` and a line in `bugs.jsonl` under
/// `SessionLog.root`, with the session log, the mic and replay state, and the last 20 s the mic heard as a WAV.
/// Nothing leaves this Mac; the bug-kit listener reads the folder as a local Mac app (`mac_dir`) and files a bead.
extension AppModel {
    /// The last month's changes by story, which `just app` bundles as whats-new.json (BugKit's `whats-new.sh`).
    static let whatsNew = WhatsNewSeen.bundledFeed()

    /// Who made a report: the app, its build and commit (`commit.txt`, "-dirty" too), the hardware model and system.
    static let bugAppInfo: BugAppInfo = {
        var info = BugAppInfo.fromMainBundle(device: "")
        info.app = "Audio Debugger"
        info.commit = buildCommit
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let system = "macOS"
        #else
        let system = "iOS"
        #endif
        info.device = "\(BugAppInfo.hardwareModel()) \(system) \(v.majorVersion).\(v.minorVersion)"
        return info
    }()

    /// The commit `just app` wrote into the bundle.
    static let buildCommit: String = {
        guard let url = Bundle.main.url(forResource: "commit", withExtension: "txt"),
            let s = try? String(contentsOf: url, encoding: .utf8)
        else { return "unknown" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// Return in the sheet: save the note with its evidence. `another` keeps the sheet open, empty, for the next.
    func saveBug(another: Bool = false) {
        let note = bugNote.trimmingCharacters(in: .whitespacesAndNewlines)
        showBugReport = another
        bugNote = ""
        guard !note.isEmpty else { return }
        SessionLog.shared.event("bug", ["note": note, "another": another])
        let writer = BugReportWriter(
            store: BugStore(documents: SessionLog.root), info: Self.bugAppInfo, logger: SessionLog.shared.bugLogger,
            copySessionLog: true, writeReportJSON: true)
        let screen = replayOpen ? "replay" : "live", context = bugContext(), position = SessionLog.shared.position
        let (audio, rate) = capture.last(seconds: replaySeconds)
        Task.detached {
            let report = await writer.save(
                note: note, screen: screen, context: context, screenshotPNG: nil, log: position,
                extraFiles: { folder in
                    SessionLog.shared.flush()  // the writer copies the log next
                    let name = "mic-last-\(replaySeconds)s.wav"
                    try writeWAV(audio, sampleRate: rate, to: folder.appendingPathComponent(name))
                    return [name]
                })
            await MainActor.run {
                Log.app.info("bug report \(report.folder, privacy: .public): \(note, privacy: .public)")
                self.bugSaved = report.folder
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    MainActor.assumeIsolated { if self.bugSaved == report.folder { self.bugSaved = nil } }
                }
            }
        }
    }

    /// A report's context: the mic, its readings, and the replay's state. Numbers stay numbers, so `jq` compares them.
    func bugContext() -> [String: JSONValue] {
        var c: [String: JSONValue] = [
            "mic": .string(mic?.name ?? "none"),
            "mics": .array(mics.map { .string($0.name) }),
            "rms_db": .double(Double(rmsDB)), "peak_db": .double(Double(peakDB)),
            "noise_floor_db": .double(Double(noiseFloorDB ?? -200)), "clips": .int(clips),
            "noise_reduction": .bool(processing.noiseReduction), "voice_boost": .bool(processing.voiceBoost),
        ]
        if let micError { c["mic_error"] = .string(micError) }
        if replayOpen {
            c["replay_time"] = .double(seconds(position))
            c["replay_duration"] = .double(seconds(replayLength))
        }
        return c
    }
}

/// Mono float32 samples to a WAV file.
func writeWAV(_ samples: [Float], sampleRate: Double, to url: URL) throws {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
        let channel = buffer.floatChannelData?[0]
    else { throw CaptureError.noFormat }
    samples.withUnsafeBufferPointer { src in
        guard let base = src.baseAddress else { return }
        channel.update(from: base, count: samples.count)
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}
