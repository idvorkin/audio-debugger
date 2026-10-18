import AppKit
import BugKit
import SwiftUI

@main
struct AudioDebuggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // Not `@State`: in the macOS 27 SDK that is a macro whose plugin ships only with Xcode, and this builds with
    // the Command Line Tools. The App is made once and the model is @Observable, so a plain property is enough.
    private let model: AppModel

    init() {
        model = AppModel()
    }

    var body: some Scene {
        Window("Audio Debugger", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    model.start()
                    Keys.install(model)
                    if let seconds = Launch.selfTestSeconds { SelfTest.run(model, after: seconds) }
                    if let dir = Launch.screenshotDir { Screenshots.run(model, into: dir) }
                }
        }
        .defaultSize(width: 1300, height: 860)
        .commands { DebuggerCommands(model: model) }

        Settings {
            // BugKit's About: version, build and commit from the built Info.plist; the stack lets it push its page.
            NavigationStack { Form { BugKitAboutLink() }.padding() }.frame(width: 420, height: 240)
        }
    }
}

/// Menus. The bare keys live in `Keys`; these are the ⌘ ones.
struct DebuggerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .help) {
            Button("Report a Bug…") { model.showBugReport = true }.keyboardShortcut("i")
            Button("What's New") { model.showWhatsNew = true }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

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

    /// A scripted run: its logs and reports go in their own folder, so the listener never files them.
    static var scripted: Bool { selfTestSeconds != nil || screenshotDir != nil }
}

/// Bare keys, handled before any focused control sees them (so Space never presses a focused button).
@MainActor
enum Keys {
    private static var monitor: Any?

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            guard mods.isEmpty else { return event }
            // Typing a bug note (or in any sheet or text field) must reach the text, not the transport.
            if model.showBugReport || model.showWhatsNew || NSApp.keyWindow?.firstResponder is NSText {
                return event
            }
            return handle(event, model) ? nil : event
        }
    }

    private static func handle(_ event: NSEvent, _ model: AppModel) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 49: model.togglePlay()  // Space: play/pause, or open the last 20 s
        case 53: model.closeReplay()  // Escape
        case 123: model.jump(seconds: shift ? -5 : -1)  // ←
        case 124: model.jump(seconds: shift ? 5 : 1)  // →
        default:
            guard let c = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if let n = Int(c), (1...9).contains(n) {
                model.select(index: n - 1)
                return true
            }
            switch c {
            case "r": model.replay(seconds: 20)
            case "t": model.replay(seconds: 10)
            case "f": model.replay(seconds: 5)
            case "a": model.restart()
            case "n": model.processing.noiseReduction.toggle()
            case "b": model.processing.voiceBoost.toggle()
            case "c": model.resetReadings()
            default: return false
            }
        }
        return true
    }
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
            model.replay(seconds: 5)
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
            model.bugNote = "selftest report"
            model.saveBug()
            await wait(1.5)
            let folder = model.bugSaved.map { SessionLog.root.appendingPathComponent($0) }  // "bugs/<time>"
            let files = folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
            Log.selftest.info(
                "bug report \(model.bugSaved ?? "none", privacy: .public): \(files.sorted().joined(separator: " "), privacy: .public)"
            )
            Log.selftest.info("selftest done")
            NSApp.terminate(nil)
        }
    }
}
