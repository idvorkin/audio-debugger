import AudioCore
import Foundation

enum Launch {
    /// `--mic NAME`: open the first mic whose name contains NAME, over the remembered one (not saved).
    static var micName: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--mic"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--selftest N`: run the scripted flow after N seconds of capture, muted, then quit.
    static var selfTestSeconds: Double? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest") else { return nil }
        return i + 1 < args.count ? Double(args[i + 1]) ?? 6 : 6
    }

    /// `--screenshots DIR`: save the window live and with a replay open into DIR, muted, then quit.
    static var screenshotDir: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    /// `--no-mic`: never ask for or open a mic, for a simulator screenshot while the Mac's input is AirPods (a
    /// simulator's mic is the Mac's default input, and opening AirPods' drops them into call mode).
    static var noMic: Bool { CommandLine.arguments.contains("--no-mic") }

    /// `--keys`: open with the key sheet up (story 016), for a screenshot.
    static var showKeys: Bool { CommandLine.arguments.contains("--keys") }

    /// A scripted run: its logs and reports go in their own folder, so the listener never files them.
    static var scripted: Bool { selfTestSeconds != nil || screenshotDir != nil || noMic }
}

/// `just selftest`: drive the replay flow muted and log what happened, then quit. Verified from the log.
@MainActor
enum SelfTest {
    static func run(_ model: AppModel, after seconds: Double) {
        model.player.muted = true
        Log.selftest.info("selftest: capturing for \(seconds, privacy: .public)s")
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            await wait(seconds)
            Log.selftest.info(
                "mic \(model.mic?.name ?? "none", privacy: .public); mics \(model.mics.count, privacy: .public); error \(model.micError ?? "none", privacy: .public)"
            )
            _ = model.press(.character("r"), shift: false)  // story 003: R is the last 5 s
            await wait(2)
            Log.selftest.info(
                "replay open \(model.replayOpen, privacy: .public) length \(model.seconds(model.replayLength), format: .fixed(precision: 2), privacy: .public)s position \(model.seconds(model.position), format: .fixed(precision: 2), privacy: .public)s playing \(model.playing, privacy: .public) busy \(model.processingBusy, privacy: .public)"
            )
            model.togglePlay()
            let paused = model.player.transport.position
            await wait(0.5)
            Log.selftest.info("paused: position held \(paused == model.player.transport.position, privacy: .public)")
            model.seek(to: model.replayLength / 2)
            Log.selftest.info(
                "seek to middle: \(model.seconds(model.position), format: .fixed(precision: 2), privacy: .public)s")
            model.processing.noiseReduction.toggle()
            await wait(1.5)
            model.processing.voiceBoost.toggle()
            await wait(1.5)
            Log.selftest.info(
                "after toggles (\(model.processing.label, privacy: .public)): position \(model.seconds(model.position), format: .fixed(precision: 2), privacy: .public)s, length \(model.seconds(model.replayLength), format: .fixed(precision: 2), privacy: .public)s"
            )
            model.processing.noiseReduction.toggle()
            model.processing.voiceBoost.toggle()
            model.restart()
            await wait(1)
            Log.selftest.info(
                "restart then 1s: position \(model.seconds(model.position), format: .fixed(precision: 2), privacy: .public)s playing \(model.playing, privacy: .public)"
            )
            model.jump(seconds: 1)
            model.closeReplay()
            // Story 016: ? opens the key sheet, keys behind it do nothing, Esc closes it; Y is the last 20 s.
            _ = model.press(.character("?"), shift: true)
            let up = model.showKeys
            _ = model.press(.character("y"), shift: false)
            let blocked = !model.replayOpen
            _ = model.press(.escape, shift: false)
            Log.selftest.info(
                "key sheet: up \(up, privacy: .public), Y blocked \(blocked, privacy: .public), closed by Esc \(!model.showKeys, privacy: .public)"
            )
            _ = model.press(.character("y"), shift: false)
            await wait(0.5)
            Log.selftest.info(
                "Y: replay \(model.seconds(model.replayLength), format: .fixed(precision: 2), privacy: .public)s")
            model.cancel()
            model.bugNote = "selftest report"
            model.saveBug()
            await wait(1.5)
            let folder = model.bugSaved.map { SessionLog.root.appendingPathComponent($0) }  // "bugs/<time>"
            let files = folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
            Log.selftest.info(
                "bug report \(model.bugSaved ?? "none", privacy: .public): \(files.sorted().joined(separator: " "), privacy: .public)"
            )
            let levels = model.levels
            Log.selftest.info(
                "noise readout: floor \(levels?.floorDB ?? -200, format: .fixed(precision: 1), privacy: .public) speech \(levels?.speechDB ?? -200, format: .fixed(precision: 1), privacy: .public) separation \(levels?.separation.rawValue ?? "none", privacy: .public)"
            )
            model.saveSample()
            await wait(1.5)
            let sample = model.sampleSaved.map { SessionLog.root.appendingPathComponent("samples/\($0)") }
            let sampleFiles = sample.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
            Log.selftest.info(
                "sample \(model.sampleSaved ?? "none", privacy: .public): \(sampleFiles.sorted().joined(separator: " "), privacy: .public)"
            )
            #if os(macOS)
            await captureSets(model)
            #endif
            Log.selftest.info("selftest done")
            quitApp()
        }
    }

    #if os(macOS)
    /// Stories 017/018: a 2 s capture set at once, then in turn, of the `--mic` mics only, so a selftest never opens
    /// AirPods or wakes an iPhone; without `--mic` it is skipped. Checks each manifest and its files.
    private static func captureSets(_ model: AppModel) async {
        guard let filter = Launch.micName else {
            Log.selftest.info("capture set: skipped (no --mic filter)")
            return
        }
        for mode in [CaptureSet.Mode.together, .inTurn] {
            model.captureSaved = nil
            model.captureSet(mode, seconds: 2, matching: filter)
            var waited = 0
            while model.captureRun != nil && waited < 60 {
                try? await Task.sleep(for: .seconds(0.5))
                waited += 1
            }
            guard let name = model.captureSaved else {
                Log.selftest.error("capture set \(mode.rawValue, privacy: .public): not saved")
                continue
            }
            let folder = SessionLog.root.appendingPathComponent("captures/\(name)")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let manifest = (try? Data(contentsOf: folder.appendingPathComponent("manifest.json")))
                .flatMap { try? CaptureSet.decode($0) }
            let streams = manifest?.streams.map { s in
                "\(s.name) \(s.rate.map { "\(Int($0)) Hz" } ?? "failed") offset \(s.offset ?? 0) open \(s.openMs ?? 0) ms"
            }
            Log.selftest.info(
                "capture set \(mode.rawValue, privacy: .public) captures/\(name, privacy: .public): \(files.sorted().joined(separator: " "), privacy: .public); streams \(streams?.joined(separator: "; ") ?? "no manifest", privacy: .public)"
            )
        }
    }
    #endif
}
