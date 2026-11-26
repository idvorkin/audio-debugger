import AudioCore
import Foundation

/// What a capture set's run is doing, for the screen: "Opening 3 mics", "Recording 7 s", or in turn the phrase and
/// whose turn it is.
struct CaptureRun: Equatable {
    var mode: CaptureSet.Mode
    var status: String
    /// In turn, while a mic is listening: the phrase to say.
    var phrase: String?
}

/// Stories 017 (M, every mic at once) and 018 (⇧M, each in turn): record the mics into one capture set,
/// `captures/<yyyyMMdd-HHmmss>/` under `SessionLog.root` (its `selftest/` for scripted runs): one raw WAV and one
/// sample sidecar (with the mic's score) per mic, and `manifest.json` (AudioCore's `CaptureSet`). Each mic gets its
/// own `Capture`; the live mic carries on. Spec: docs/specs/2026-11-26-compare-mics.md.
extension AppModel {
    /// M / ⇧M. A scripted run (selftest) keeps only the `--mic` mics and takes 2 s each, and refuses without `--mic`,
    /// so a script never opens AirPods or wakes a phone.
    func captureSet(_ mode: CaptureSet.Mode) {
        guard captureRun == nil else { return }
        let filter = Launch.scripted ? Launch.micName : nil
        if Launch.scripted && filter == nil {
            Log.app.error("capture set refused: a scripted run needs --mic to choose its mics")
            return
        }
        let chosen = mode.mics(from: mics, matching: filter)
        guard !chosen.isEmpty else {
            Log.app.info("capture set: no mics to capture (\(mode.rawValue, privacy: .public))")
            captureRun = CaptureRun(mode: mode, status: "No mics to capture")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { self.captureRun = nil } }
            return
        }
        let secs: Double = Launch.scripted ? 2 : (mode == .together ? 10 : 6)
        SessionLog.shared.event(
            "capture_set_start", ["mode": mode.rawValue, "mics": chosen.map(\.name), "seconds": secs])
        // Set now, not in the task: a second M, or a caller waiting on the run, sees it at once.
        captureRun = CaptureRun(mode: mode, status: "Starting")
        captureTask = Task { @MainActor in
            var set = CaptureSet(created: Date(), mode: mode, seconds: secs)
            set.commit = Self.buildCommit
            let takes =
                mode == .together
                ? await recordTogether(chosen, seconds: secs) : await recordInTurn(chosen, seconds: secs)
            if takes.allSatisfy({ $0.samples.isEmpty && $0.error == nil }) {
                Log.app.info("capture set stopped before any take")
                captureRun = nil
                return
            }
            let offsets =
                mode == .together
                ? CaptureSet.offsets(
                    ends: takes.map(\.end), lengths: takes.map { Double($0.samples.count) / $0.rate })
                : takes.map { _ in 0 }
            for (i, take) in takes.enumerated() {
                let index = i + 1
                var stream = CaptureSet.Stream(
                    index: index, name: take.mic.name, uid: take.mic.uid, kind: take.mic.kind, openMs: take.openMs,
                    error: take.error)
                if take.error == nil && !take.samples.isEmpty {
                    stream.rate = take.rate
                    stream.file = CaptureSet.fileStem(index: index, name: take.mic.name) + ".wav"
                    stream.offset = (offsets[i] * 1000).rounded() / 1000
                    stream.started = take.end - Double(take.samples.count) / take.rate
                } else if stream.error == nil {
                    stream.error = "stopped before this mic's turn"
                }
                set.streams.append(stream)
            }
            captureRun = CaptureRun(mode: mode, status: "Saving")
            await save(set, takes)
        }
    }

    /// Esc while a set is being taken: at once, nothing is saved; in turn, the takes so far are.
    func stopCaptureSet() {
        captureTask?.cancel()
    }

    private func recordTogether(_ mics: [Mic], seconds: Double) async -> [Take] {
        captureRun = CaptureRun(mode: .together, status: "Opening \(mics.count) mic\(mics.count == 1 ? "" : "s")")
        let captures = mics.map { _ in Capture() }
        // Every open starts now, each on its own capture's queue; the take starts once they have all opened or
        // failed, so every stream covers the same span (a Bluetooth mic can take seconds).
        let opens = zip(captures, mics).map { capture, mic in Task { await Self.open(capture, mic.uid) } }
        var results: [(Result<Double, Error>, Int)] = []
        for open in opens { results.append(await open.value) }
        defer { for capture in captures { capture.stop() } }
        for (mic, (result, ms)) in zip(mics, results) {
            let outcome = (try? result.get()).map { "\($0) Hz" } ?? "failed"
            Log.mic.info("capture set: \(mic.name, privacy: .public) \(outcome, privacy: .public) in \(ms) ms")
        }
        guard results.contains(where: { (try? $0.0.get()) != nil }) else {
            return zip(mics, results).map { Take(mic: $0, openMs: $1.1, error: Self.reason($1.0)) }
        }
        for left in stride(from: Int(seconds.rounded(.up)), to: 0, by: -1) {
            captureRun = CaptureRun(mode: .together, status: "Recording every mic: \(left) s")
            do { try await Task.sleep(for: .seconds(1)) } catch { return [] }
        }
        return zip(zip(mics, captures), results).map { pair, opened in
            let (mic, capture) = pair
            guard case .success = opened.0 else {
                return Take(mic: mic, openMs: opened.1, error: Self.reason(opened.0))
            }
            let t = capture.take(seconds: seconds)
            return Take(mic: mic, openMs: opened.1, samples: t.samples, rate: t.rate, end: t.end)
        }
    }

    private func recordInTurn(_ mics: [Mic], seconds: Double) async -> [Take] {
        var takes: [Take] = []
        for (i, mic) in mics.enumerated() {
            let turn = "\(mic.name), \(i + 1) of \(mics.count)"
            captureRun = CaptureRun(mode: .inTurn, status: "Opening \(turn)")
            let capture = Capture()
            let (result, ms) = await Self.open(capture, mic.uid)
            Log.mic.info("capture set in turn: \(turn, privacy: .public) opened in \(ms) ms")
            guard case .success = result else {
                capture.stop()
                takes.append(Take(mic: mic, openMs: ms, error: Self.reason(result)))
                continue
            }
            var stopped = false
            for left in stride(from: Int(seconds.rounded(.up)), to: 0, by: -1) {
                captureRun = CaptureRun(mode: .inTurn, status: "\(turn): \(left) s", phrase: CaptureSet.phrase)
                do { try await Task.sleep(for: .seconds(1)) } catch {
                    stopped = true
                    break
                }
            }
            capture.stop()
            if stopped { break }
            let t = capture.take(seconds: seconds)
            takes.append(Take(mic: mic, openMs: ms, samples: t.samples, rate: t.rate, end: t.end))
        }
        return takes
    }

    private func save(_ set: CaptureSet, _ takes: [Take]) async {
        let name = Self.captureStamp.string(from: set.created)
        let folder = SessionLog.root.appendingPathComponent("captures/\(name)", isDirectory: true)
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (stream, take) in zip(set.streams, takes) {
                    guard let file = stream.file else { continue }
                    try writeWAV(take.samples, sampleRate: take.rate, to: folder.appendingPathComponent(file))
                    var sidecar = sampleSidecar(
                        take.samples, rate: take.rate, mic: take.mic.name, commit: set.commit ?? "")
                    sidecar.merge(Self.scoreFields(take.samples, rate: take.rate)) { _, b in b }
                    let json = try JSONSerialization.data(
                        withJSONObject: sidecar, options: [.prettyPrinted, .sortedKeys])
                    let stem = (file as NSString).deletingPathExtension
                    try json.write(to: folder.appendingPathComponent(stem + ".json"))
                }
                try set.encoded().write(to: folder.appendingPathComponent("manifest.json"))
            }.value
            let ok = set.streams.filter { $0.file != nil }.count
            SessionLog.shared.event(
                "capture_set_saved",
                ["folder": name, "mode": set.mode.rawValue, "streams": set.streams.count, "recorded": ok])
            Log.app.info(
                "saved capture set captures/\(name, privacy: .public): \(ok) of \(set.streams.count) mics recorded")
            captureSaved = name
            #if os(macOS)
            openComparison(folder)  // story 019: the set just taken opens for comparison
            #endif
        } catch {
            Log.app.error("capture set failed: \(String(describing: error), privacy: .public)")
            captureRun = CaptureRun(mode: set.mode, status: "Could not save: \(error.localizedDescription)")
            try? await Task.sleep(for: .seconds(4))
        }
        captureRun = nil
    }

    private static func open(_ capture: Capture, _ uid: String) async -> (Result<Double, Error>, Int) {
        let start = Date()
        let result = await withCheckedContinuation { done in capture.start(uid: uid) { done.resume(returning: $0) } }
        return (result, Int(Date().timeIntervalSince(start) * 1000))
    }

    private static func reason(_ result: Result<Double, Error>) -> String? {
        if case .failure(let error) = result { return String(describing: error) }
        return nil
    }

    /// The mic's score (AudioCore's `MicScore`, Grabber's) for the sidecar; `score_floor_db` is not the readout's floor.
    nonisolated static func scoreFields(_ x: [Float], rate: Double) -> [String: Any] {
        let r = MicScore.measure(x, sampleRate: rate)
        var d: [String: Any] = [
            "score": r.score, "score_pieces": r.pieces, "score_clipped_pieces": r.clips,
            "score_dropout_pieces": r.dropouts,
        ]
        if let v = r.floorDB { d["score_floor_db"] = jsonNumber(v, places: 1) }
        if let v = r.speechDB { d["score_speech_db"] = jsonNumber(v, places: 1) }
        if let v = r.snrDB { d["snr_db"] = jsonNumber(v, places: 1) }
        return d
    }

    private static let captureStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

/// One mic's take: its samples, or why there are none.
struct Take: Sendable {
    var mic: Mic
    var openMs: Int
    var samples: [Float] = []
    var rate: Double = 48_000
    var end: TimeInterval = 0
    var error: String?
}
