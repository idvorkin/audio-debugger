import AppKit

/// `just screenshots`: the app, muted, sizes its window, lets the spectrogram fill, then names its window (a
/// `<shot>.wid` file holding the window number) for each shot; the recipe captures it with `screencapture -l`, which
/// needs the terminal's Screen Recording permission, not the app's. Quits when done.
@MainActor
enum Screenshots {
    static func run(_ model: AppModel, into dir: URL) {
        model.player.muted = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                Log.selftest.error("screenshots: no window")
                quitApp()
                return
            }
            window.setContentSize(NSSize(width: 1300, height: 860))
            await wait(8)
            mark("live", window, dir)
            await wait(2)
            model.replay(seconds: 10)
            await wait(3)
            mark("replay", window, dir)
            await wait(2)
            model.closeReplay()
            Log.selftest.info("screenshots done")
            quitApp()
        }
    }

    private static func mark(_ shot: String, _ window: NSWindow, _ dir: URL) {
        let file = dir.appendingPathComponent("\(shot).wid")
        try? String(window.windowNumber).write(to: file, atomically: true, encoding: .utf8)
        Log.selftest.info("screenshot \(shot, privacy: .public): window \(window.windowNumber, privacy: .public)")
    }
}
