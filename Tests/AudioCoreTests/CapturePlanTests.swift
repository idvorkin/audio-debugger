import Testing

@testable import AudioCore

// Stories 017/018: the capture picker's choices.

private let airpods = Mic(uid: "a", name: "AirPods", kind: .bluetooth)
private let macbook = Mic(uid: "b", name: "MacBook", kind: .builtIn)
private let iphone = Mic(uid: "c", name: "iPhone", kind: .continuity)
private let usbMic = Mic(uid: "d", name: "USB", kind: .usb)
private let all = [airpods, macbook, iphone, usbMic]

@Test func safeMicsStartOnRiskyOnesOff() {
    let p = CapturePlan(mics: all, remembered: nil, mode: .together)
    #expect(p.selected == [macbook, usbMic])
    #expect(CapturePlan.risk(airpods) != nil)
    #expect(CapturePlan.risk(iphone) != nil)
    #expect(CapturePlan.risk(usbMic) == nil)
}

@Test func rememberedChoiceWinsWhenPresent() {
    #expect(CapturePlan(mics: all, remembered: ["a", "d"], mode: .together).selected == [airpods, usbMic])
    // Nothing remembered is plugged in: back to the safe defaults.
    #expect(CapturePlan(mics: all, remembered: ["gone"], mode: .together).selected == [macbook, usbMic])
}

@Test func digitsSwitchMicsInListOrder() {
    var p = CapturePlan(mics: all, remembered: nil, mode: .together)
    p.toggle(0)  // AirPods on
    p.toggle(1)  // MacBook off
    p.toggle(9)  // no such mic: nothing
    #expect(p.selected == [airpods, usbMic])
}

@Test func modeAndSecondsStayInRange() {
    var p = CapturePlan(mics: all, remembered: nil, mode: .together)
    #expect(p.seconds == 10)
    p.toggleMode()
    #expect(p.mode == .inTurn)
    for _ in 0..<20 { p.adjust(by: 1) }
    #expect(p.seconds == 15)
    for _ in 0..<20 { p.adjust(by: -1) }
    #expect(p.seconds == 2)
    #expect(CapturePlan(mics: all, remembered: nil, mode: .inTurn).seconds == 6)
}
