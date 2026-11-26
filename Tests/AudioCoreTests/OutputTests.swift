import Testing

@testable import AudioCore

// Story 020: the replay's output, chosen apart from the mic.

private let speakers = Output(uid: "spk", name: "MacBook Pro Speakers")
private let phones = Output(uid: "hp", name: "External Headphones")
private let usb = Output(uid: "usb", name: "USB DAC")

@Test func noChoiceMeansTheSystemDefault() {
    let c = OutputChoice(wanted: nil, outputs: [speakers, phones])
    #expect(c.active == nil)
    #expect(c.missing == false)
}

@Test func aChosenOutputIsUsedWhilePresent() {
    let c = OutputChoice(wanted: "hp", outputs: [speakers, phones])
    #expect(c.active == phones)
    #expect(c.missing == false)
}

@Test func anUnpluggedChoiceFallsBackAndIsKept() {
    let c = OutputChoice(wanted: "hp", outputs: [speakers])
    #expect(c.active == nil)
    #expect(c.missing)
    #expect(c.wanted == "hp")
    // Plugged back in: used again.
    #expect(OutputChoice(wanted: c.wanted, outputs: [speakers, phones]).active == phones)
}

@Test func nextStepsThroughDefaultThenEachOutput() {
    let outputs = [speakers, phones, usb]
    var c = OutputChoice(wanted: nil, outputs: outputs)
    var seen: [String?] = []
    for _ in 0..<4 {
        c = c.next()
        seen.append(c.wanted)
    }
    #expect(seen == ["spk", "hp", "usb", nil])
}

@Test func nextFromAMissingChoiceStartsAtTheFirstOutput() {
    let c = OutputChoice(wanted: "gone", outputs: [speakers, phones])
    #expect(c.next().wanted == "spk")
}
