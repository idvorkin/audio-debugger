import AVFoundation
import AudioCore
import CoreMedia
import os

let replaySeconds = 20
let scopeSize = 4096

/// The mic side: an AVCaptureSession on one device (picked by its Core Audio UID), delivering mono float32 at the
/// device's own rate into the replay ring and the scope window. The main thread reads snapshots under the same lock.
///
/// Not AVAudioEngine: on macOS its input runs through a private aggregate device ("CADefaultDeviceAggregate"),
/// and pointing that at an input-only USB mic delivered nothing but zeros.
final class Capture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private struct Buffers {
        var ring = RingBuffer(capacity: 1)
        var scope = RingBuffer(capacity: scopeSize)
        var clips = 0
        /// False once stopped, so a buffer still in flight on the capture queue is dropped.
        var running = true
    }

    private var session: AVCaptureSession?
    private var errorObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "capture", qos: .userInteractive)
    private let buffers = OSAllocatedUnfairLock(initialState: Buffers())
    private(set) var sampleRate: Double = 48_000
    /// Called on the main queue when the session fails at runtime (the device went away, say).
    var onFailure: (() -> Void)?

    func start(uid: String) throws {
        stop()
        guard let device = AVCaptureDevice(uniqueID: uid) else { throw CaptureError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)
        let rate =
            CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription)?
            .pointee.mSampleRate ?? 48_000
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureError.cannotAdd }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        sampleRate = rate
        let capacity = replaySeconds * Int(rate)
        buffers.withLock { $0 = Buffers(ring: RingBuffer(capacity: capacity)) }
        errorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Log.mic.error("capture runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self?.onFailure?()
        }
        session.startRunning()
        self.session = session
        Log.mic.info("capture started: \(device.localizedName, privacy: .public) at \(rate, privacy: .public) Hz")
    }

    func stop() {
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
        session?.stopRunning()
        session = nil
        // The live view must not keep analysing the last window as if it were live; the replay ring stays.
        buffers.withLock {
            $0.running = false
            $0.scope.reset()
        }
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
        let samples = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self),
            count: Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size)
        let clipped = samples.reduce(0) { $0 + (abs($1) >= 0.999 ? 1 : 0) }
        buffers.withLock {
            guard $0.running else { return }
            $0.ring.write(samples)
            $0.scope.write(samples)
            $0.clips += clipped
        }
    }

    /// The newest scope window (zero-padded while young), the clip count and how much has been captured.
    func snapshot() -> (scope: [Float], clips: Int, captured: Int) {
        buffers.withLock { b in
            let s = b.scope.last(scopeSize)
            return ([Float](repeating: 0, count: scopeSize - s.count) + s, b.clips, b.ring.total)
        }
    }

    func last(seconds: Int) -> [Float] {
        let n = seconds * Int(sampleRate)
        return buffers.withLock { $0.ring.last(n) }
    }

    func resetClips() { buffers.withLock { $0.clips = 0 } }
}

enum CaptureError: Error, CustomStringConvertible {
    case noDevice, cannotAdd, noFormat

    var description: String {
        switch self {
        case .noDevice: "the mic is not available to capture (unplugged?)"
        case .cannotAdd: "the capture session refused the mic"
        case .noFormat: "no usable audio format"
        }
    }
}
