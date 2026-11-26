import AudioCore
import CoreAudio
import Foundation

/// The Mac's mics: every Core Audio device with an input channel, by its UID (which `AVCaptureDevice` opens).
enum Mics {
    /// Every device with at least one input channel.
    static func all() -> [Mic] {
        devices().compactMap { id in
            guard channels(id, kAudioDevicePropertyScopeInput) > 0, let (uid, name) = named(id) else { return nil }
            return Mic(uid: uid, name: name, kind: kind(transportType(id)))
        }
    }

    /// Story 020: every device with at least one output channel, for replay.
    static func outputs() -> [Output] {
        devices().compactMap { id in
            guard channels(id, kAudioDevicePropertyScopeOutput) > 0, let (uid, name) = named(id) else { return nil }
            return Output(uid: uid, name: name)
        }
    }

    /// The Core Audio device with `uid`, for pointing the replay engine at it.
    static func deviceID(uid: String) -> AudioDeviceID? {
        devices().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func devices() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// The UID and name, leaving out the system's private aggregates (not a real mic or speaker).
    private static func named(_ id: AudioDeviceID) -> (String, String)? {
        guard let name = string(id, kAudioObjectPropertyName), let uid = string(id, kAudioDevicePropertyDeviceUID),
            !name.hasPrefix("CADefaultDeviceAggregate")
        else { return nil }
        return (uid, name)
    }

    /// Calls `handler` on the main queue whenever a device is plugged in or removed.
    static func onChange(_ handler: @escaping () -> Void) {
        var addr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            handler()
        }
    }

    /// The input the open `mic` really is, for the line under the mic bar (story 015). On the Mac it is the device
    /// itself; opening a Bluetooth headset's mic is what puts it into call (hands-free) mode.
    static func input(for mic: Mic) -> (name: String, callMode: Bool) { (mic.name, mic.isBluetooth) }

    /// The Mac has no audio-session route to follow: a device that changes reopens through `onChange` or a capture
    /// error, which brings its new rate with it.
    static func onRouteChange(_ handler: @escaping () -> Void) {}

    private static func kind(_ transport: UInt32) -> Mic.Kind {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        // An iPhone's mic over Continuity: "ccwd" (cable) and "ccwl" (wireless), as Core Audio reports them.
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            .continuity
        default: .other
        }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }
}
