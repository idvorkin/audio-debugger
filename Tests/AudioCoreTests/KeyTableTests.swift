import Foundation
import Testing

@testable import AudioCore

// Story 016: the key sheet, the iPad's commands and the stories' "Keys at a glance" are one table.

@Test func keyTableMatchesTheStoriesTable() throws {
    let readme = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/stories/README.md")
    let text = try String(contentsOf: readme, encoding: .utf8)
    let section = try #require(text.components(separatedBy: "## Keys at a glance").last)
    let rows = section.split(separator: "\n").map(String.init)
        .filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Key ") }
    #expect(rows == KeyTable.markdownRows)
}

// Story 003 and the change's intent: R, T and Y replay 5, 10 and 20 s, and no other key replays.
@Test func replayKeysPlayFiveTenTwentySeconds() {
    #expect(KeyTable.replaySeconds == ["r": 5, "t": 10, "y": 20])
}

@Test func replayKeysAreCommands() {
    let replay = KeyTable.all.first { $0.keys == "R / T / Y" }
    #expect(replay?.commands.map(\.key) == ["r", "t", "y"])
}

@Test func everyCommandIsUnique() {
    let commands = KeyTable.all.flatMap(\.commands).map { "\($0.key)\($0.shift)" }
    #expect(Set(commands).count == commands.count)
}
