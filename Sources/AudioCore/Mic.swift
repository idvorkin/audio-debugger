/// An input as the platform reports it: a Core Audio device on the Mac, an audio-session input port on iOS. The list
/// is each platform's (`Mics.all()` in Mac/Mics+Mac.swift and iOS/Mics+iOS.swift); the choice is shared.
public struct Mic: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case builtIn, usb, bluetooth, wired, other
    }

    public let uid: String
    public let name: String
    public let kind: Kind

    public init(uid: String, name: String, kind: Kind) {
        self.uid = uid
        self.name = name
        self.kind = kind
    }

    public var id: String { uid }
    public var isBluetooth: Bool { kind == .bluetooth }

    /// The mic to open: the one asked for if present, else a USB mic, else a wired headset's (iOS), else the built-in
    /// one. Never Bluetooth unless it is all there is: opening an AirPods mic drops them into low-quality headset
    /// mode, music and all.
    public static func choose(from mics: [Mic], wanted uid: String?) -> Mic? {
        if let uid, let m = mics.first(where: { $0.uid == uid }) { return m }
        for kind: Kind in [.usb, .wired, .builtIn] {
            if let m = mics.first(where: { $0.kind == kind }) { return m }
        }
        return mics.first { !$0.isBluetooth } ?? mics.first
    }
}
