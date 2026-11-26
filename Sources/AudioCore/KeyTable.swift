/// Story 016: every key the app answers, in one table. The key sheet (?) shows it, the iPad registers its bare keys
/// as keyboard commands from it (so holding ⌘ lists them), and a host test checks it against the stories' "Keys at a
/// glance", so the three never drift.
public struct KeyEntry: Sendable, Equatable {
    /// How the key reads on the sheet and in the docs: "R / T / Y", "Esc or ⌘.".
    public let keys: String
    public let action: String
    /// The single bare keys this row stands for, as iPad keyboard commands: a character ("r", "?"), or "space",
    /// "escape", "left", "right". Empty for rows the screen handles itself (the mic digits) or ⌘ menu items.
    public let commands: [Command]

    public struct Command: Sendable, Equatable {
        public let key: String
        public let title: String
        public let shift: Bool

        public init(_ key: String, _ title: String, shift: Bool = false) {
            self.key = key
            self.title = title
            self.shift = shift
        }
    }

    public init(_ keys: String, _ action: String, _ commands: [Command] = []) {
        self.keys = keys
        self.action = action
        self.commands = commands
    }
}

public enum KeyTable {
    public static let all: [KeyEntry] = [
        KeyEntry("1–9", "Switch to that mic; in a capture set, play that row raw"),
        KeyEntry(
            "Space", "Play / pause the replay; with none open, replay the last 20 s", [.init("space", "Play / Pause")]),
        KeyEntry(
            "R / T / Y", "Replay the last 5 / 10 / 20 s",
            [.init("r", "Replay Last 5 s"), .init("t", "Replay Last 10 s"), .init("y", "Replay Last 20 s")]),
        KeyEntry("A", "Replay from the start", [.init("a", "Replay From the Start")]),
        KeyEntry(
            "← / → (⇧ for 5 s)", "Jump back / forward 1 s",
            [
                .init("left", "Back 1 s"), .init("right", "Forward 1 s"), .init("left", "Back 5 s", shift: true),
                .init("right", "Forward 5 s", shift: true),
            ]),
        KeyEntry(
            "N / B", "Noise reduction / voice boost on and off",
            [.init("n", "Noise Reduction On/Off"), .init("b", "Voice Boost On/Off")]),
        KeyEntry(
            "C", "Reset held peaks, clip count and the noise readout", [.init("c", "Reset Peaks and Noise Readout")]),
        KeyEntry("S", "Save the last 20 s as a WAV with its measurements", [.init("s", "Save Sample")]),
        // Mac only (stories 017/018), so no iPad command.
        KeyEntry(
            "M / ⇧M",
            "Mac: pick mics to capture into one set, at once / in turn; in the picker 1–9 switch a mic, T at once or in "
                + "turn, ← / → seconds, Return starts (Esc stops)"),
        KeyEntry("O", "Mac: replay on the next output (system default, then each speaker or headphone)"),
        KeyEntry("⇥", "Capture set: back to the row played before, at the same place (A/B)"),
        KeyEntry("⌘O / ⌘R", "Mac: open a capture set / reveal the open set, else the last sample, in Finder"),
        KeyEntry("⇧⌘S", "Share the open capture set, else the last sample (AirDrop, Messages, Mail, Files…)"),
        KeyEntry(
            "H", "Open the noise explainer (what floor, speech and separation mean)", [.init("h", "Noise Explainer")]),
        KeyEntry("?", "Show every key", [.init("?", "Show Every Key")]),
        KeyEntry("Esc or ⌘.", "Close the key sheet, else the replay, else the capture set"),
        KeyEntry("⌘I", "Report a bug"),
        KeyEntry("⇧⌘N", "What's new"),
    ]

    /// Story 003: how many seconds each replay key plays, shortest first along the keyboard.
    public static let replaySeconds: [String: Int] = ["r": 5, "t": 10, "y": 20]

    /// The rows as the stories' markdown table rows: "| R / T / Y | Replay the last … |".
    public static var markdownRows: [String] { all.map { "| \($0.keys) | \($0.action) |" } }
}
