import AudioCore
import Foundation
import os

let replaySeconds = 20
let scopeSize = 4096

/// The mic side: a `MicSource` (each platform's: Mac/MicSource+Mac.swift, iOS/MicSource+iOS.swift) on one mic,
/// delivering mono float32 at the device's own rate into the 20 s replay ring and the scope window. The main thread
/// reads snapshots under the same lock.
final class Capture: @unchecked Sendable {
    private struct Buffers {
        var ring = RingBuffer(capacity: 1)
        var scope = RingBuffer(capacity: scopeSize)
        var clips = 0
        /// False once stopped, so a buffer still in flight on the capture queue is dropped.
        var running = true
    }

    private var source: MicSource?
    private let buffers = OSAllocatedUnfairLock(initialState: Buffers())
    private(set) var sampleRate: Double = 48_000
    /// Called on the main queue when the source fails at runtime (the device went away, an interruption ended).
    var onFailure: (() -> Void)?

    func start(uid: String) throws {
        stop()
        let source = try MicSource(
            uid: uid, deliver: { [weak self] samples in self?.ingest(samples) },
            onFailure: { [weak self] in self?.onFailure?() })
        try source.start()
        // After the start, so a source that fails to start loses nothing. At the same rate the ring carries on: a
        // reopen (iOS reopens on every route change and interruption) keeps the last 20 s, with a gap in them.
        sampleRate = source.sampleRate
        let capacity = replaySeconds * Int(source.sampleRate)
        buffers.withLock { b in
            if b.ring.capacity == capacity {
                b.running = true
                b.scope.reset()
            } else {
                b = Buffers(ring: RingBuffer(capacity: capacity))
            }
        }
        self.source = source
        Log.mic.info("capture started: \(source.name, privacy: .public) at \(source.sampleRate, privacy: .public) Hz")
    }

    func stop() {
        source?.stop()
        source = nil
        // The live view must not keep analysing the last window as if it were live; the replay ring stays.
        buffers.withLock {
            $0.running = false
            $0.scope.reset()
        }
    }

    /// On the source's own thread.
    private func ingest(_ samples: UnsafeBufferPointer<Float>) {
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
