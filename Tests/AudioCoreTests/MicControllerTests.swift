import Foundation
import Testing

@testable import AudioCore

// The mic open, fallback and retry chain (MicController), driven as AppModel drives it. The S-numbers are PR #3's
// scenarios, which ran in a throwaway harness on wall-clock time; here time is a value, so none can flake.

private let builtIn = Mic(uid: "builtin", name: "MacBook Pro Microphone", kind: .builtIn)
private let usb = Mic(uid: "usb", name: "USBAudio1.0", kind: .usb)
private let wired = Mic(uid: "wired", name: "Headset Microphone", kind: .wired)
private let car = Mic(uid: "car", name: "Model Y", kind: .bluetooth)
private let airPods = Mic(uid: "airpods", name: "AirPods Pro", kind: .bluetooth)

private func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 1_000_000 + seconds) }

private func noDevices() -> [Mic] {
    Issue.record("the device list was read")
    return []
}

private func retries(_ effects: [MicController.Effect]) -> [Double] {
    effects.compactMap { if case .scheduleRetry(let s) = $0 { s } else { nil } }
}

/// A controller with `m` open (generation 1) at time 0, from a first device list of `list`.
private func started(on m: Mic, list: [Mic]) -> MicController {
    var c = MicController(micName: nil)
    #expect(c.devicesChanged(list, authorized: true, remembered: m.uid, now: at(0)) == [.open(m, generation: 1)])
    #expect(c.opened(generation: 1, rate: 48_000, now: at(0.25)) == [.didOpen(m, rate: 48_000, ms: 250)])
    return c
}

// MARK: Choosing

@Test func choiceOrder() {
    #expect(Mic.choose(from: [builtIn, usb, car], wanted: "car") == car)  // the remembered one, Bluetooth or not
    #expect(Mic.choose(from: [builtIn, wired, usb], wanted: "gone") == usb)
    #expect(Mic.choose(from: [builtIn, wired, airPods], wanted: nil) == wired)
    #expect(Mic.choose(from: [airPods, builtIn], wanted: nil) == builtIn)
    #expect(Mic.choose(from: [airPods], wanted: nil) == airPods)  // Bluetooth only when it is all there is
    #expect(Mic.choose(from: [], wanted: nil) == nil)
}

@Test func firstLoadOpensTheBestAndNeverAirPodsByAccident() {
    var c = MicController(micName: nil)
    #expect(
        c.devicesChanged([airPods, builtIn], authorized: true, remembered: nil, now: at(0)) == [
            .open(builtIn, generation: 1)
        ])
    #expect(c.mic == nil)  // `mic` is only ever an open mic
    #expect(c.opening == builtIn)
    #expect(c.opened(generation: 1, rate: 48_000, now: at(0.375)) == [.didOpen(builtIn, rate: 48_000, ms: 375)])
    #expect(c.mic == builtIn)
    #expect(c.error == nil)
}

@Test func micNameArgumentWinsOverTheRememberedMic() {
    var c = MicController(micName: "macbook")
    #expect(
        c.devicesChanged([usb, builtIn], authorized: true, remembered: "usb", now: at(0)) == [
            .open(builtIn, generation: 1)
        ])
}

@Test func theUSBMicComesBackWhenReplugged() {
    var c = started(on: usb, list: [builtIn, usb])
    #expect(
        c.devicesChanged([builtIn], authorized: true, remembered: "usb", now: at(5)) == [
            .open(builtIn, generation: 2)
        ])
    _ = c.opened(generation: 2, rate: 48_000, now: at(5.5))
    #expect(
        c.devicesChanged([builtIn, usb], authorized: true, remembered: "usb", now: at(9)) == [
            .open(usb, generation: 3)
        ])
}

@Test func anUnchangedChoiceDoesNotReopen() {
    var c = started(on: usb, list: [builtIn, usb])
    #expect(c.devicesChanged([builtIn, usb, airPods], authorized: true, remembered: "usb", now: at(5)).isEmpty)
}

// MARK: Picking (PR #3: S1-S3, S7)

@Test func s1ThePickerKeepsTheOldMicUntilTheNewOneOpens() {
    var c = started(on: usb, list: [builtIn, usb, car])
    #expect(c.select(car, now: at(10)) == [.open(car, generation: 2)])
    #expect(c.mic == usb)
    #expect(c.opened(generation: 2, rate: 16_000, now: at(11.75)) == [.didOpen(car, rate: 16_000, ms: 1750)])
    #expect(c.mic == car)
}

@Test func s2ASecondTapWhileOpeningIsIgnored() {
    var c = started(on: usb, list: [builtIn, usb, car])
    #expect(c.select(car, now: at(10)) == [.open(car, generation: 2)])
    #expect(c.select(car, now: at(10.5)).isEmpty)
    #expect(c.opened(generation: 2, rate: 16_000, now: at(11.75)) == [.didOpen(car, rate: 16_000, ms: 1750)])
    #expect(c.mic == car)
    #expect(c.error == nil)
}

@Test func s3TheNewestPickWins() {
    var c = started(on: builtIn, list: [builtIn, usb, car])
    #expect(c.select(car, now: at(10)) == [.open(car, generation: 2)])
    #expect(c.select(usb, now: at(10.5)) == [.open(usb, generation: 3)])
    #expect(c.opened(generation: 2, rate: 16_000, now: at(11.75)).isEmpty)  // superseded: never becomes `mic`
    #expect(c.mic == builtIn)
    #expect(c.opened(generation: 3, rate: 48_000, now: at(12)) == [.didOpen(usb, rate: 48_000, ms: 1500)])
    #expect(c.mic == usb)
}

@Test func s7APickThatWillNotOpenFallsBackAndSaysWhy() {
    var c = started(on: usb, list: [builtIn, usb, car])
    #expect(c.select(car, now: at(10)) == [.open(car, generation: 2)])
    #expect(
        c.failedToOpen(generation: 2, error: "fake mic refused", now: at(10.5)) == [
            .didFail(car, error: "fake mic refused", ms: 500), .open(usb, generation: 3),
        ])
    #expect(c.mic == nil)
    #expect(c.opened(generation: 3, rate: 48_000, now: at(11)) == [.didOpen(usb, rate: 48_000, ms: 500)])
    #expect(c.mic == usb)
    #expect(c.error == "Model Y: fake mic refused")
}

// MARK: Failures while opening (S4, S5)

@Test func s4TheOldMicFailingWhileANewOneOpensLeavesThePick() {
    var c = started(on: usb, list: [builtIn, usb, car])
    _ = c.select(car, now: at(10))
    #expect(c.captureFailed(remembered: "car", now: at(10.5), devices: noDevices) == [.failedWhileOpening])
    #expect(c.opened(generation: 2, rate: 16_000, now: at(11)) == [.didOpen(car, rate: 16_000, ms: 1000)])
    #expect(c.mic == car)
}

@Test func s5AFailureAfterItsOpensResultReopensTheMic() {
    var c = started(on: usb, list: [builtIn, usb, car])
    _ = c.select(car, now: at(10))
    _ = c.opened(generation: 2, rate: 16_000, now: at(11))
    // Capture delivers the failure after the open's result.
    #expect(
        c.captureFailed(remembered: "car", now: at(11), devices: { [builtIn, usb, car] }) == [
            .reopening, .open(car, generation: 3),
        ])
    #expect(c.opened(generation: 3, rate: 16_000, now: at(12)) == [.didOpen(car, rate: 16_000, ms: 1000)])
    #expect(c.mic == car)
    #expect(c.error == nil)
}

// MARK: Retries (S8, S11, the 2 s throttle)

@Test func s8EveryMicRefusingRetriesIn3SecondsUntilOneOpens() {
    var c = MicController(micName: nil)
    #expect(
        c.devicesChanged([builtIn, usb], authorized: true, remembered: nil, now: at(0)) == [
            .open(usb, generation: 1)
        ])
    #expect(
        c.failedToOpen(generation: 1, error: "refused", now: at(0.25)) == [
            .didFail(usb, error: "refused", ms: 250), .open(builtIn, generation: 2),
        ])
    #expect(
        c.failedToOpen(generation: 2, error: "refused", now: at(0.5)) == [
            .didFail(builtIn, error: "refused", ms: 250), .stop, .scheduleRetry(after: 3),
        ])
    #expect(c.mic == nil)
    #expect(c.error == "MacBook Pro Microphone: refused")  // a real error is not replaced by "No microphone found."
    #expect(
        c.retryFired(remembered: nil, now: at(3.5), devices: { [builtIn, usb] }) == [
            .reopening, .open(usb, generation: 4),
        ])
    #expect(c.opened(generation: 4, rate: 48_000, now: at(3.75)) == [.didOpen(usb, rate: 48_000, ms: 250)])
    #expect(c.error == nil)
}

@Test func aDeviceChangeIsANewChanceForMicsThatFailed() {
    var c = MicController(micName: nil)
    _ = c.devicesChanged([usb], authorized: true, remembered: nil, now: at(0))
    #expect(retries(c.failedToOpen(generation: 1, error: "refused", now: at(0.1))) == [3])
    #expect(c.devicesChanged([usb], authorized: true, remembered: nil, now: at(1)) == [.open(usb, generation: 3)])
}

@Test func anOpenByAnotherWayCancelsThePendingRetry() {
    var c = MicController(micName: nil)
    _ = c.devicesChanged([builtIn, usb], authorized: true, remembered: nil, now: at(0))
    _ = c.failedToOpen(generation: 1, error: "refused", now: at(0.1))
    _ = c.failedToOpen(generation: 2, error: "refused", now: at(0.2))
    #expect(c.retryPending)
    #expect(c.select(usb, now: at(1)) == [.open(usb, generation: 4)])
    #expect(
        c.opened(generation: 4, rate: 48_000, now: at(1.5)) == [
            .cancelRetry, .didOpen(usb, rate: 48_000, ms: 500),
        ])
    #expect(!c.retryPending)
}

@Test func s11EveryMicLeavingDuringAnOpenStopsAndRetries() {
    var c = MicController(micName: nil)
    #expect(c.devicesChanged([usb], authorized: true, remembered: nil, now: at(0)) == [.open(usb, generation: 1)])
    #expect(c.devicesChanged([], authorized: true, remembered: nil, now: at(0.5)) == [.stop, .scheduleRetry(after: 3)])
    #expect(c.error == "No microphone found.")
    #expect(c.opening == nil)
    #expect(c.opened(generation: 1, rate: 48_000, now: at(1)).isEmpty)  // the stop closed the open in flight
    #expect(c.mic == nil)
    #expect(c.retryFired(remembered: nil, now: at(3.5), devices: { [usb] }) == [.reopening, .open(usb, generation: 3)])
    #expect(c.opened(generation: 3, rate: 48_000, now: at(4)) == [.didOpen(usb, rate: 48_000, ms: 500)])
    #expect(c.error == nil)
}

@Test func aFailureWithin2SecondsOfAReopenWaitsAndOnlyOneRetryIsPending() {
    var c = started(on: usb, list: [builtIn, usb])
    #expect(
        c.captureFailed(remembered: "usb", now: at(10), devices: { [builtIn, usb] }) == [
            .reopening, .open(usb, generation: 2),
        ])
    _ = c.opened(generation: 2, rate: 48_000, now: at(10.5))
    #expect(
        c.captureFailed(remembered: "usb", now: at(11), devices: noDevices) == [
            .failedTooSoon(wait: 1), .scheduleRetry(after: 1.1),
        ])
    #expect(c.error == "Capture failed; retrying in 1 s")
    #expect(c.mic == usb)
    let again = c.captureFailed(remembered: "usb", now: at(11.5), devices: noDevices)
    #expect(retries(again).isEmpty)  // two failures together must not start two retry chains
    #expect(c.error == "Capture failed; retrying in 1 s")
    #expect(
        c.retryFired(remembered: "usb", now: at(12.1), devices: { [builtIn, usb] }) == [
            .reopening, .open(usb, generation: 3),
        ])
}

// MARK: Permission (S9, S9b-d)

private let denied = "Microphone access denied — allow it in System Settings → Privacy & Security → Microphone."

@Test func s9DeniedAHotPlugRefreshesTheListAndKeepsTheMessage() {
    var c = MicController(micName: nil)
    c.accessDenied(denied)
    #expect(c.devicesChanged([builtIn, usb], authorized: false, remembered: nil, now: at(0)).isEmpty)
    #expect(c.mics == [builtIn, usb])
    #expect(c.error == denied)
    #expect(!c.retryPending)
}

@Test func s9bAGrantLaterOpensOnTheNextDeviceChange() {
    var c = MicController(micName: nil)
    c.accessDenied(denied)
    _ = c.devicesChanged([builtIn, usb], authorized: false, remembered: nil, now: at(0))
    #expect(
        c.devicesChanged([builtIn, usb], authorized: true, remembered: nil, now: at(5)) == [
            .open(usb, generation: 1)
        ])
    _ = c.opened(generation: 1, rate: 48_000, now: at(5.5))
    #expect(c.error == nil)
}

@Test func s9cAHotPlugWhileThePermissionDialogIsUpOpensNothing() {
    var c = MicController(micName: nil)
    #expect(c.devicesChanged([builtIn, usb], authorized: false, remembered: nil, now: at(0)).isEmpty)
    #expect(c.error == nil)
    // The grant: AppModel's answer handler runs the device-list change again, now authorized.
    #expect(
        c.devicesChanged([builtIn, usb], authorized: true, remembered: nil, now: at(2)) == [
            .open(usb, generation: 1)
        ])
}

@Test func s9dTappingAMicWhileDeniedStillTriesAndRetries() {
    // Observed in PR #3, and kept as it was: only the device-list change is gated on the permission.
    var c = MicController(micName: nil)
    c.accessDenied(denied)
    _ = c.devicesChanged([builtIn, usb], authorized: false, remembered: nil, now: at(0))
    #expect(c.select(builtIn, now: at(1)) == [.open(builtIn, generation: 1)])
    #expect(
        c.failedToOpen(generation: 1, error: "refused", now: at(1.25)) == [
            .didFail(builtIn, error: "refused", ms: 250), .open(usb, generation: 2),
        ])
    #expect(
        c.failedToOpen(generation: 2, error: "refused", now: at(1.5)) == [
            .didFail(usb, error: "refused", ms: 250), .stop, .scheduleRetry(after: 3),
        ])
    #expect(c.error == "MacBook Pro Microphone: refused")
}

// MARK: Device changes during an open (S10, S10b)

@Test func s10ADeviceChangeTreatsTheOpeningMicAsCurrent() {
    var c = MicController(micName: nil)
    #expect(
        c.devicesChanged([builtIn, usb, car], authorized: true, remembered: "car", now: at(0)) == [
            .open(car, generation: 1)
        ])
    #expect(c.devicesChanged([builtIn, usb, car, airPods], authorized: true, remembered: "car", now: at(0.5)).isEmpty)
    #expect(c.opened(generation: 1, rate: 16_000, now: at(1.75)) == [.didOpen(car, rate: 16_000, ms: 1750)])
}

@Test func s10bTheOpeningMicLeavingMovesOnToTheNextBest() {
    var c = MicController(micName: nil)
    _ = c.devicesChanged([builtIn, usb, car], authorized: true, remembered: "car", now: at(0))
    #expect(
        c.devicesChanged([builtIn, usb], authorized: true, remembered: "car", now: at(0.5)) == [
            .open(usb, generation: 2)
        ])
    #expect(c.opened(generation: 1, rate: 16_000, now: at(1.8)).isEmpty)
    #expect(c.opened(generation: 2, rate: 48_000, now: at(1)) == [.didOpen(usb, rate: 48_000, ms: 500)])
    #expect(c.mic == usb)
}
