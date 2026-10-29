import Foundation

/// An input as the platform reports it: a Core Audio device on the Mac, an audio-session input port on iOS.
struct Mic: Identifiable, Hashable {
    enum Kind: String {
        case builtIn, usb, bluetooth, wired, other
    }

    let uid: String
    let name: String
    let kind: Kind

    var id: String { uid }
    var isBluetooth: Bool { kind == .bluetooth }
}

/// `all()` and `onChange(_:)` are each platform's (Mac/Mics+Mac.swift, iOS/Mics+iOS.swift); the choice is shared.
extension Mics {
    /// The mic to open: the one asked for if present, else a USB mic, else a wired headset's (iOS), else the built-in
    /// one. Never Bluetooth unless it is all there is: opening an AirPods mic drops them into low-quality headset
    /// mode, music and all.
    static func choose(from mics: [Mic], wanted uid: String?) -> Mic? {
        if let uid, let m = mics.first(where: { $0.uid == uid }) { return m }
        for kind: Mic.Kind in [.usb, .wired, .builtIn] {
            if let m = mics.first(where: { $0.kind == kind }) { return m }
        }
        return mics.first { !$0.isBluetooth } ?? mics.first
    }
}
