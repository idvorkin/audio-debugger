import AVFoundation

/// iOS's mics: the audio session's input ports (built-in, wired headset, USB, Bluetooth), by port UID. The session
/// picks which one the input engine hears (`setPreferredInput`, in `MicSource`).
enum Mics {
    /// Once, before anything reads the inputs: `availableInputs` lists only what the category allows.
    ///
    /// - `.playAndRecord`: the mic and the replay together.
    /// - `.measurement`: no automatic gain, no voice processing; the raw mic is what this app is for.
    /// - `.defaultToSpeaker`: replay from the speaker, not the earpiece, when nothing is plugged in.
    /// - `.allowBluetoothHFP`: lists AirPods' mic (chosen last, as on the Mac; opening it drops them to call mode).
    /// - `.allowBluetoothA2DP`: replay to AirPods in full quality while another mic is open.
    /// - `.mixWithOthers`: background capture is not cut off by music or another app's audio, and does not stop it.
    static func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
            Log.mic.info("audio session: playAndRecord, measurement")
        } catch {
            Log.mic.error("audio session category failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func all() -> [Mic] {
        (AVAudioSession.sharedInstance().availableInputs ?? []).map { port in
            Mic(uid: port.uid, name: port.portName, kind: kind(port.portType))
        }
    }

    /// Calls `handler` on the main queue when an input is plugged in or removed. Only those two reasons: our own
    /// `setPreferredInput` changes the route too, and reopening on that would loop.
    static func onChange(_ handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                reason == .newDeviceAvailable || reason == .oldDeviceUnavailable
            else { return }
            handler()
        }
    }

    static func port(uid: String) -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?.first { $0.uid == uid }
    }

    private static func kind(_ type: AVAudioSession.Port) -> Mic.Kind {
        switch type {
        case .builtInMic: .builtIn
        case .usbAudio: .usb
        case .bluetoothHFP, .bluetoothLE: .bluetooth
        case .headsetMic, .lineIn: .wired
        default: .other
        }
    }
}
