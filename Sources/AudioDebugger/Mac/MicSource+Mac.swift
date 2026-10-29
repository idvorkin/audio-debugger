import AVFoundation
import CoreMedia

/// The Mac's mic: an AVCaptureSession on one device, picked by its Core Audio UID, converting to mono float32 at the
/// device's own rate.
///
/// Not AVAudioEngine: on macOS its input runs through a private aggregate device ("CADefaultDeviceAggregate"),
/// and pointing that at an input-only USB mic delivered nothing but zeros.
final class MicSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let sampleRate: Double
    let name: String
    private let session = AVCaptureSession()
    private let deliver: (UnsafeBufferPointer<Float>) -> Void
    private let onFailure: () -> Void
    private var errorObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "capture", qos: .userInteractive)

    init(
        uid: String, deliver: @escaping (UnsafeBufferPointer<Float>) -> Void, onFailure: @escaping () -> Void
    ) throws {
        guard let device = AVCaptureDevice(uniqueID: uid) else { throw CaptureError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)
        let rate =
            CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription)?
            .pointee.mSampleRate ?? 48_000
        sampleRate = rate
        name = device.localizedName
        self.deliver = deliver
        self.onFailure = onFailure
        super.init()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureError.cannotAdd }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
    }

    func start() throws {
        errorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Log.mic.error("capture runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self?.onFailure()
        }
        session.startRunning()
    }

    func stop() {
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
        session.stopRunning()
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        var list = AudioBufferList()
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block)
        guard status == noErr, let data = list.mBuffers.mData else { return }
        deliver(
            UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size))
    }
}
