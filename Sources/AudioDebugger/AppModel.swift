import AVFoundation
import AudioCore
import BugKit
import CoreGraphics
import Foundation
import Observation

/// Which processing a replay clip has; each combination is computed once per replay and cached.
struct Processing: Hashable {
    var noiseReduction: Bool
    var voiceBoost: Bool

    var label: String {
        [noiseReduction ? "denoise" : nil, voiceBoost ? "boost" : nil].compactMap { $0 }.joined(separator: "+")
    }
}

/// One min/max column of the replay envelope.
struct EnvelopeColumn {
    let low: Float
    let high: Float
}

private enum Key {
    static let mic = "micUID"
    static let noiseReduction = "noiseReduction"
    static let voiceBoost = "voiceBoost"
}

@MainActor @Observable
final class AppModel {
    // Mics
    private(set) var mics: [Mic] = []
    private(set) var mic: Mic?
    private(set) var micError: String?

    // Live readings, refreshed 30 times a second.
    private(set) var waveform: [Float] = []
    private(set) var spectrum: [Float] = []
    private(set) var spectrumPeak: [Float] = []
    private(set) var frequencies: [Float] = []
    private(set) var spectrogram: CGImage?
    private(set) var rmsDB: Float = -200
    private(set) var peakDB: Float = -200
    private(set) var heldPeakDB: Float = -120
    private(set) var noiseFloorDB: Float?
    private(set) var dominantHz: Float = 0
    private(set) var pitchHz: Float = 0
    private(set) var clips = 0
    var hint: GainHint { GainHint(peakDB: peakDB, heldPeakDB: heldPeakDB) }

    // Replay
    private(set) var replayOpen = false
    private(set) var replayLength = 0
    private(set) var position = 0
    private(set) var playing = false
    private(set) var envelope: [EnvelopeColumn] = []
    private(set) var processingBusy = false
    var processing: Processing {
        didSet {
            UserDefaults.standard.set(processing.noiseReduction, forKey: Key.noiseReduction)
            UserDefaults.standard.set(processing.voiceBoost, forKey: Key.voiceBoost)
            if oldValue != processing { applyProcessing(keepPlace: true) }
        }
    }
    var replaySampleRate: Double { clipRate }

    // Bug reports and What's new (BugKit; BugReport.swift)
    var showBugReport = false
    var bugNote = ""
    var bugSaved: String?
    var showWhatsNew = false

    let capture = Capture()
    let player = Player()
    private var analyzer = SpectrumAnalyzer(size: scopeSize, sampleRate: 48_000)
    private var pitch = PitchDetector(size: scopeSize, sampleRate: 48_000)
    private var gram = Spectrogram(width: 300, height: 256)
    private var floor = NoiseFloor()
    private var rawClip: [Float] = []
    private var clipRate: Double = 48_000
    private var processed: [Processing: [Float]] = [:]
    private var timer: Timer?
    private var lastLevelLog = Date.distantPast
    private var lastReopen = Date.distantPast
    private var processGeneration = 0

    init() {
        // BugKit's crash capture, first: a signal or uncaught exception writes a file in `<root>/crashes/`,
        // announced once at the next launch as `crash_report` (the listener files it).
        let crashes = SessionLog.root.appendingPathComponent("crashes", isDirectory: true)
        CrashReports.shared.install(folder: crashes, logger: SessionLog.shared.bugLogger)
        SessionLog.shared.event(
            "launch", ["commit": Self.buildCommit, "args": Array(CommandLine.arguments.dropFirst())])
        SessionLog.shared.prune()
        let d = UserDefaults.standard
        processing = Processing(
            noiseReduction: d.object(forKey: Key.noiseReduction) as? Bool ?? true,
            voiceBoost: d.object(forKey: Key.voiceBoost) as? Bool ?? true)
    }

    func start() {
        capture.onFailure = { [weak self] in
            guard let self else { return }
            // At most one reopen every 2 s, so a mic that keeps failing can never loop.
            guard Date().timeIntervalSince(self.lastReopen) > 2 else {
                Log.mic.error("capture failed again within 2 s of a reopen; leaving it")
                return
            }
            self.lastReopen = Date()
            Log.mic.info("capture failed; reopening the mic")
            self.reopenMic()
        }
        Mics.onChange { [weak self] in self?.micsChanged() }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor [weak self] in
                Log.mic.info("microphone access: \(granted ? "granted" : "denied", privacy: .public)")
                guard let self else { return }
                if granted {
                    self.micsChanged()
                } else {
                    self.micError =
                        "Microphone access denied — allow it in System Settings → Privacy & Security → Microphone."
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Mics

    /// The device list changed (or first load): reopen the wanted mic when it is back, fall back when it left.
    private func micsChanged() {
        mics = Mics.all()
        Log.mic.info("mics: \(self.mics.map(\.name).joined(separator: ", "), privacy: .public)")
        SessionLog.shared.event("mics", ["names": mics.map(\.name)])
        let named = Launch.micName.flatMap { n in mics.first { $0.name.localizedCaseInsensitiveContains(n) }?.uid }
        let wanted = named ?? UserDefaults.standard.string(forKey: Key.mic)
        guard let pick = Mics.choose(from: mics, wanted: wanted) else {
            capture.stop()
            mic = nil
            micError = "No microphone found."
            return
        }
        if pick.uid != mic?.uid || !mics.contains(where: { $0.id == mic?.id }) { open(pick) }
    }

    /// The user picked a mic: remember it, so it comes back by itself after being unplugged.
    func select(_ m: Mic) {
        UserDefaults.standard.set(m.uid, forKey: Key.mic)
        SessionLog.shared.event("select_mic", ["name": m.name])
        open(m)
    }

    func select(index: Int) {
        guard mics.indices.contains(index) else { return }
        select(mics[index])
    }

    private func reopenMic() {
        if let mic { open(mic) }
    }

    private func open(_ m: Mic) {
        do {
            try capture.start(uid: m.uid)
            mic = m
            micError = nil
            let rate = capture.sampleRate
            analyzer = SpectrumAnalyzer(size: scopeSize, sampleRate: rate)
            pitch = PitchDetector(size: scopeSize, sampleRate: Float(rate))
            frequencies = analyzer.frequencies
            resetReadings()
            Log.mic.info(
                "opened \(m.name, privacy: .public) (\(m.uid, privacy: .public)) at \(rate, privacy: .public) Hz")
            SessionLog.shared.event("mic_open", ["name": m.name, "uid": m.uid, "rate": rate])
        } catch {
            mic = m
            micError = "\(m.name): \(error)"
            SessionLog.shared.event("mic_error", ["name": m.name, "error": "\(error)"])
            Log.mic.error("could not open \(m.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func resetReadings() {
        gram.clear()
        floor = NoiseFloor()
        heldPeakDB = -120
        spectrumPeak = []
        capture.resetClips()
    }

    // MARK: Live readings

    private func tick() {
        let snap = capture.snapshot()
        let window = snap.scope
        waveform = Array(window.suffix(2048))
        let recent = window.suffix(2048)
        rmsDB = decibels(rms(recent))
        peakDB = decibels(peak(recent))
        heldPeakDB = max(heldPeakDB - 0.3, peakDB)
        // Not until the scope window is real audio: its zero padding is not the room.
        if snap.captured >= scopeSize { floor.update(rmsDB: rmsDB) }
        noiseFloorDB = floor.db
        clips = snap.clips

        let db = analyzer.decibelSpectrum(window)
        spectrum = db
        spectrumPeak = spectrumPeak.count == db.count ? zip(spectrumPeak, db).map { max($0 - 0.2, $1) } : db
        let freqs = analyzer.frequencies  // not `frequencies`: empty until a mic opens (the permission prompt)
        if let k = db.indices.max(by: { db[$0] < db[$1] }), freqs.indices.contains(k) { dominantHz = freqs[k] }
        pitchHz = pitch.pitch(window)

        let binHz = Float(analyzer.sampleRate) / Float(scopeSize)
        gram.push(Array(db.prefix(min(db.count, Int(8000 / binHz)))))
        spectrogram = makeImage(gram)

        let t = player.transport
        position = t.position
        playing = t.playing

        if Date().timeIntervalSince(lastLevelLog) >= 1 {
            lastLevelLog = Date()
            SessionLog.shared.event(
                "level",
                [
                    "mic": mic?.name as Any, "rms": rmsDB, "peak": peakDB, "floor": noiseFloorDB as Any,
                    "pitch": pitchHz, "clips": clips, "captured": snap.captured,
                ])
            Log.level.info(
                "\(self.mic?.name ?? "-", privacy: .public) rms \(self.rmsDB, format: .fixed(precision: 1), privacy: .public) peak \(self.peakDB, format: .fixed(precision: 1), privacy: .public) floor \(self.noiseFloorDB ?? 0, format: .fixed(precision: 1), privacy: .public) pitch \(noteName(self.pitchHz), privacy: .public) clips \(self.clips, privacy: .public) captured \(snap.captured, privacy: .public)"
            )
        }
    }

    private func makeImage(_ g: Spectrogram) -> CGImage? {
        let data = g.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: g.width, height: g.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: g.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Replay

    /// Open replay on the last `seconds` of the mic, processed as the toggles say, and play it.
    func replay(seconds: Int) {
        let clip = capture.last(seconds: seconds)
        guard !clip.isEmpty else {
            Log.replay.info("replay \(seconds, privacy: .public)s: nothing captured yet")
            return
        }
        rawClip = clip
        clipRate = capture.sampleRate
        processed = [:]
        replayLength = clip.count
        replayOpen = true
        SessionLog.shared.event(
            "replay",
            [
                "asked": seconds, "seconds": Double(clip.count) / clipRate, "peak": decibels(peak(clip[...])),
                "rms": decibels(rms(clip[...])), "processing": processing.label,
            ])
        Log.replay.info(
            "replay \(seconds, privacy: .public)s: \(Double(clip.count) / self.clipRate, format: .fixed(precision: 1), privacy: .public)s captured, peak \(decibels(peak(clip[...])), format: .fixed(precision: 1), privacy: .public) dB, rms \(decibels(rms(clip[...])), format: .fixed(precision: 1), privacy: .public) dB"
        )
        applyProcessing(keepPlace: false)
    }

    /// Put the clip for the current toggles into the player, computing it off the main thread the first time.
    private func applyProcessing(keepPlace: Bool) {
        guard replayOpen else { return }
        let want = processing
        if let ready = processed[want] {
            load(ready, keepPlace: keepPlace)
            return
        }
        processGeneration += 1
        let generation = processGeneration
        let raw = rawClip, rate = Float(clipRate)
        processingBusy = true
        Task.detached(priority: .userInitiated) {
            let started = Date()
            var y = raw
            if want.noiseReduction { y = denoise(y) }
            y = want.voiceBoost ? voiceBoost(y, sampleRate: rate) : normalizePeak(y)
            let ms = Date().timeIntervalSince(started) * 1000
            let out = y
            await MainActor.run { [weak self] in
                guard let self, generation == self.processGeneration else { return }
                self.processed[want] = out
                self.processingBusy = false
                SessionLog.shared.event(
                    "processed",
                    [
                        "processing": want.label, "ms": ms, "rms": decibels(rms(out[...])),
                        "peak": decibels(peak(out[...])),
                    ])
                Log.replay.info(
                    "processed \(want.label.isEmpty ? "normalized" : want.label, privacy: .public) in \(ms, format: .fixed(precision: 0), privacy: .public) ms: rms \(decibels(rms(out[...])), format: .fixed(precision: 1), privacy: .public) dB, peak \(decibels(peak(out[...])), format: .fixed(precision: 1), privacy: .public) dB"
                )
                if self.processing == want { self.load(out, keepPlace: keepPlace) }
            }
        }
    }

    private func load(_ clip: [Float], keepPlace: Bool) {
        do {
            try player.load(clip, sampleRate: clipRate, keepPlace: keepPlace)
            if !keepPlace { player.play() }
            envelope = AudioCore.envelope(clip, buckets: 1200).map { EnvelopeColumn(low: $0.min, high: $0.max) }
        } catch {
            Log.replay.error("playback failed: \(String(describing: error), privacy: .public)")
        }
    }

    func togglePlay() {
        guard replayOpen else { return replay(seconds: replaySeconds) }
        player.togglePlay()
        SessionLog.shared.event(
            player.transport.playing ? "play" : "pause", ["at": seconds(player.transport.position)])
        Log.replay.info(
            "\(self.player.transport.playing ? "play" : "pause", privacy: .public) at \(self.seconds(self.player.transport.position), format: .fixed(precision: 2), privacy: .public)s"
        )
    }

    func restart() {
        guard replayOpen else { return }
        player.restart()
        SessionLog.shared.event("restart")
        Log.replay.info("replay from the start")
    }

    func seek(to sample: Int) {
        guard replayOpen else { return }
        player.seek(to: sample)
        position = player.transport.position
    }

    func jump(seconds delta: Double) {
        seek(to: player.transport.position + Int(delta * clipRate))
        SessionLog.shared.event("jump", ["by": delta, "to": seconds(position)])
        Log.replay.info(
            "jump \(delta, privacy: .public)s to \(self.seconds(self.position), format: .fixed(precision: 2), privacy: .public)s"
        )
    }

    func closeReplay() {
        guard replayOpen else { return }
        player.close()
        replayOpen = false
        processGeneration += 1
        processingBusy = false
        SessionLog.shared.event("replay_closed")
        Log.replay.info("replay closed")
    }

    func seconds(_ samples: Int) -> Double { Double(samples) / clipRate }
}
