import AudioCore
import Foundation
import os

let replaySeconds = 20
let scopeSize = 4096

/// The mic side: a `MicSource` (each platform's: Mac/MicSource+Mac.swift, iOS/MicSource+iOS.swift) on one mic,
/// delivering mono float32 at the device's own rate into the 20 s replay ring and the scope window. The main thread
/// reads snapshots under the same lock.
///
/// Opening and closing run on a queue of their own, never the main thread: a Bluetooth mic's route takes seconds to
/// come up (1.8 s for a car's hands-free mic, a hang on the phone: ad-pdv). Requests run in order, so the last wins.
final class Capture: @unchecked Sendable {
    private struct Buffers {
        var ring = RingBuffer(capacity: 1)
        var scope = RingBuffer(capacity: scopeSize)
        var clips = 0
        /// False once stopped, so a buffer still in flight on the capture queue is dropped.
        var running = true
        var rate: Double = 48_000
    }

    private let queue = DispatchQueue(label: "mic-open", qos: .userInitiated)
    private var source: MicSource?  // on `queue` only
    /// The open source's number, on `queue` only: a failure from a source since closed is dropped.
    private var current = 0
    private let buffers = OSAllocatedUnfairLock(initialState: Buffers())
    /// Called on the main queue when the source fails at runtime (the device went away, an interruption ended).
    var onFailure: (() -> Void)?

    /// Closes the open mic and opens `uid`; `done` gets the mic's rate, or why it would not open, on the main queue.
    func start(uid: String, done: @escaping @MainActor (Result<Double, Error>) -> Void) {
        queue.async { [self] in
            let result = Result { try open(uid: uid) }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }

    func stop() { queue.async { [self] in close() } }

    private func open(uid: String) throws -> Double {
        close()
        current += 1
        let token = current
        let source = try MicSource(
            uid: uid, deliver: { [weak self] samples in self?.ingest(samples) },
            onFailure: { [weak self] in self?.sourceFailed(token) })
        try source.start()
        // After the start, so a source that fails to start loses nothing. At the same rate the ring carries on: a
        // reopen (iOS reopens on every route change and interruption) keeps the last 20 s, with a gap in them.
        let rate = source.sampleRate
        let capacity = replaySeconds * Int(rate)
        buffers.withLock { b in
            if b.ring.capacity == capacity {
                b.running = true
                b.scope.reset()
            } else {
                b = Buffers(ring: RingBuffer(capacity: capacity), rate: rate)
            }
        }
        self.source = source
        Log.mic.info("capture started: \(source.name, privacy: .public) at \(rate, privacy: .public) Hz")
        return rate
    }

    /// Through `queue`, so a failure posted while its open was finishing reaches the main queue after that open's
    /// `done`, and one from a source already closed or replaced never does.
    private func sourceFailed(_ token: Int) {
        queue.async { [self] in
            guard token == current, source != nil else { return }
            DispatchQueue.main.async { [self] in onFailure?() }
        }
    }

    private func close() {
        current += 1
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

    /// The newest `seconds` of the ring and their rate, read together: a mic reopening at another rate swaps both.
    func last(seconds: Int) -> (samples: [Float], rate: Double) {
        buffers.withLock { ($0.ring.last(seconds * Int($0.rate)), $0.rate) }
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
