import AudioCore
import SwiftUI

/// A bare key, as each platform names it: the Mac's `Keys` monitor and the iPad's hardware keyboard both land here.
enum BareKey: Equatable {
    case space, escape, left, right
    case character(String)

    /// A `KeyTable` command's key ("space", "left", "r").
    init(command key: String) {
        switch key {
        case "space": self = .space
        case "escape": self = .escape
        case "left": self = .left
        case "right": self = .right
        default: self = .character(key)
        }
    }

    /// The same key for SwiftUI's keyboard shortcuts (the iPad's keyboard commands).
    var equivalent: KeyEquivalent {
        switch self {
        case .space: .space
        case .escape: .escape
        case .left: .leftArrow
        case .right: .rightArrow
        case .character(let c): KeyEquivalent(Character(c))
        }
    }
}

extension AppModel {
    /// The bare keys (stories 01, 02, 016): true when one did something. What each key is called lives in
    /// AudioCore's `KeyTable`, which the key sheet shows.
    func press(_ key: BareKey, shift: Bool) -> Bool {
        // Behind the key sheet nothing else runs; Esc closes it.
        if showKeys {
            if key == .escape { showKeys = false }
            return true
        }
        switch key {
        case .space: togglePlay()  // play/pause, or open the last 20 s
        case .escape: closeReplay()
        case .left: jump(seconds: shift ? -5 : -1)
        case .right: jump(seconds: shift ? 5 : 1)
        case .character(let raw):
            // Opens only, never toggles: on the iPad a key can reach both a command and the screen.
            if raw == "?" {
                showKeys = true
                SessionLog.shared.event("key_sheet")
                return true
            }
            let c = raw.lowercased()
            if let n = Int(c), (1...9).contains(n) {
                select(index: n - 1)
                return true
            }
            switch c {
            case "r", "f": replay(seconds: 5)  // F: the old 5 s key, kept as an alias
            case "t": replay(seconds: 10)
            case "y": replay(seconds: 20)
            case "a": restart()
            case "n": processing.noiseReduction.toggle()
            case "b": processing.voiceBoost.toggle()
            case "c": resetReadings()
            case "s": saveSample()
            case "h": openNoiseGuide()
            default: return false
            }
        }
        return true
    }

    /// ⌘. (the iPad's Folio has no Esc): the key sheet first, else the replay.
    func cancel() {
        if showKeys { showKeys = false } else { closeReplay() }
    }
}

/// Story 016: ?, every key and what it does (AudioCore's `KeyTable`, the stories' "Keys at a glance").
struct KeySheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyList()
            HStack {
                Spacer()
                Button("Done") { model.showKeys = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }
}

/// The key sheet's title and table: plain text, so `just screenshots` can draw it with `ImageRenderer`.
struct KeyList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keys").font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(KeyTable.all, id: \.keys) { entry in
                    GridRow {
                        Text(entry.keys).font(.system(.body, design: .monospaced)).bold()
                        Text(entry.action).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

#if !os(macOS)
/// The bare keys and ⌘. as keyboard commands, so an iPad lists them when ⌘ is held (story 016). Each goes through
/// `AppModel.press`, as the Mac's key monitor does. On iPadOS 15 and later a focused text field sees a key before
/// these, so typing a bug note never reaches the transport. The Mac's bare keys are its key monitor's, not menus.
struct KeyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Replay") {
            ForEach(KeyTable.all.flatMap(\.commands), id: \.title) { command in
                Button(command.title) {
                    guard !model.showWhatsNew else { return }
                    _ = model.press(BareKey(command: command.key), shift: command.shift)
                }
                .keyboardShortcut(BareKey(command: command.key).equivalent, modifiers: command.shift ? .shift : [])
            }
            Divider()
            Button("Close Replay") { model.cancel() }.keyboardShortcut(".", modifiers: .command)
        }
    }

    /// The bare keys these commands own; the screen's own key handler leaves them alone, so none fires twice. Not
    /// "?": typed with ⇧, it may not match a command without one, so the screen opens the sheet too (opening twice
    /// is harmless).
    static let owned: Set<String> = Set(KeyTable.all.flatMap(\.commands).map(\.key)).subtracting(["?"])
}
#endif
