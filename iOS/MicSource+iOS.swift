import AVFoundation

/// iOS's mic: the audio session routed to one input port, heard through an AVAudioEngine input tap, channel 0 as
/// mono float32 at the hardware rate.
///
/// AVAudioEngine here, not the Mac's AVCaptureSession: iOS has no aggregate device in the way, and an engine tap keeps
/// running in the background (UIBackgroundModes audio), which an always-on replay needs.
final class MicSource {
    let sampleRate: Double
    let name: String
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let deliver: (UnsafeBufferPointer<Float>) -> Void
    private let onFailure: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        uid: String, deliver: @escaping (UnsafeBufferPointer<Float>) -> Void, onFailure: @escaping () -> Void
    ) throws {
        guard let port = Mics.port(uid: uid) else { throw CaptureError.noDevice }
        let session = AVAudioSession.sharedInstance()
        try session.setPreferredInput(port)
        try session.setActive(true)
        // Read after activation: the input node's format is the route's, and it is 0 Hz without the permission.
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noFormat }
        self.format = format
        sampleRate = format.sampleRate
        name = session.currentRoute.inputs.first?.portName ?? port.portName
        self.deliver = deliver
        self.onFailure = onFailure
        if name != port.portName {
            Log.mic.error(
                "asked for \(port.portName, privacy: .public), the route has \(self.name, privacy: .public)")
        }
    }

    func start() throws {
        let deliver = self.deliver
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            deliver(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        engine.prepare()
        try engine.start()
        let center = NotificationCenter.default
        // The route's format changed (a mic unplugged, a call), which stops the engine: reopen.
        observers.append(
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) {
                [weak self] _ in
                Log.mic.error("input engine configuration changed; reopening")
                self?.onFailure()
            })
        // A call or Siri took the mic, which stops the engine. Fail at once, so the live view stops showing the last
        // window as if live; the model retries until the mic opens again, as `.ended` may come late or never.
        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                Log.mic.info("audio session interruption \(type == .began ? "began" : "ended", privacy: .public)")
                self?.onFailure()
            })
        observers.append(
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) {
                [weak self] _ in
                Log.mic.error("media services were reset; reopening")
                Mics.configureSession()
                self?.onFailure()
            })
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
