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

/// The end of a scripted run (`SelfTest`, `Screenshots`).
@MainActor
func quitApp() { NSApp.terminate(nil) }

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

    /// The key code to a `BareKey`; what each does is `AppModel.press` (Keys.swift, shared with the iPad).
    private static func handle(_ event: NSEvent, _ model: AppModel) -> Bool {
        let key: BareKey
        switch event.keyCode {
        case 49: key = .space
        case 53: key = .escape
        case 123: key = .left
        case 124: key = .right
        default:
            guard let c = event.charactersIgnoringModifiers else { return false }
            key = .character(c)
        }
        return model.press(key, shift: event.modifierFlags.contains(.shift))
    }
}
