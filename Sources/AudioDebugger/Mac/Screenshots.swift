import AppKit
import SwiftUI

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
            // Story 019: M takes a (2 s, --mic only) capture set, which opens for comparison; 1 plays its first row.
            _ = model.press(.character("m"), shift: false)
            for _ in 0..<40 where model.comparison == nil { await wait(0.25) }
            _ = model.press(.character("1"), shift: false)
            await wait(1)
            mark("compare", window, dir)
            await wait(2)
            model.cancel()
            model.cancel()
            // Story 021: M's picker (opened directly: a scripted M skips it). Esc closes it; nothing opens.
            model.openCapturePicker(.together)
            await wait(1)
            mark("picker", window, dir)
            await wait(2)
            model.cancel()
            // Story 016: the key sheet. It is a window attached to the main one, which `screencapture -l` can't grab
            // while the app is in the background ("could not create image from window"), so the app draws the sheet's
            // table to keys.png itself and the recipe copies it.
            renderKeys(into: dir, scale: window.backingScaleFactor)
            Log.selftest.info("screenshots done")
            quitApp()
        }
    }

    /// The key sheet's table, as the dark sheet shows it, drawn to keys.png without Screen Recording.
    private static func renderKeys(into dir: URL, scale: CGFloat) {
        let view = KeyList()
            .frame(width: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            Log.selftest.error("screenshot keys: nothing drawn")
            return
        }
        do {
            try png.write(to: dir.appendingPathComponent("keys.png"))
            Log.selftest.info("screenshot keys: drawn \(image.width)x\(image.height)")
        } catch {
            Log.selftest.error("screenshot keys: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func mark(_ shot: String, _ window: NSWindow, _ dir: URL) {
        let file = dir.appendingPathComponent("\(shot).wid")
        try? String(window.windowNumber).write(to: file, atomically: true, encoding: .utf8)
        Log.selftest.info("screenshot \(shot, privacy: .public): window \(window.windowNumber, privacy: .public)")
    }
}
