import AVFoundation
import AudioCore
import os

/// The replay side: its own engine on the default output, pulling from a clip through `Transport` on the render
/// thread, so pause, seek and swapping in a processed clip are just state changes. Mono into the main mixer, which
/// feeds both ears.
///
/// Real-time safety: the render callback only *tries* the lock (a busy lock costs one silent buffer, never a wait),
/// and replaced clips are released after the lock is dropped, so freeing megabytes never happens under it.
final class Player {
    private struct State {
        var clip: [Float] = []
        var transport = Transport()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var engine: AVAudioEngine?
    private var engineRate: Double = 0
    private var configObserver: NSObjectProtocol?
    var muted = false {
        didSet { engine?.mainMixerNode.outputVolume = muted ? 0 : 1 }
    }

    var transport: Transport { state.withLock { $0.transport } }

    /// Swap in a clip. `keepPlace` keeps position and play state (a processing toggle); otherwise start from the top.
    func load(_ clip: [Float], sampleRate: Double, keepPlace: Bool) throws {
        var old: [Float] = []
        state.withLock { s in
            old = s.clip
            s.clip = clip
            if keepPlace {
                s.transport.load(length: clip.count)
            } else {
                s.transport = Transport(length: clip.count)
            }
        }
        old = []  // released here, outside the lock
        if engine == nil || engineRate != sampleRate || engine?.isRunning == false {
            try makeEngine(sampleRate: sampleRate)
        }
    }

    func play() {
        resume()
        state.withLock { $0.transport.play() }
    }
    func togglePlay() {
        resume()
        state.withLock { $0.transport.togglePlay() }
    }
    func restart() {
        resume()
        state.withLock { $0.transport.restart() }
    }
    func seek(to sample: Int) { state.withLock { $0.transport.seek(to: sample) } }

    func close() {
        var old = State()
        state.withLock { swap(&old, &$0) }
        old = State()  // released outside the lock
        stopEngine()
        engineRate = 0  // closed on purpose: `resume` must not bring it back
    }

    /// An interruption (a call, Siri, an alarm) stops the engine and nothing restarts it; without this, Play would
    /// show Pause over silence with the playhead frozen. Rebuilt on the same transport, as an output change is.
    /// A rebuild that failed (pressed while the interruption still holds the session) leaves no engine, so the next
    /// press tries again. The transport is paused first: the interruption stopped the sound, so Play must play.
    private func resume() {
        guard engine?.isRunning != true, engineRate > 0 else { return }
        state.withLock { $0.transport.pause() }
        do {
            try makeEngine(sampleRate: engineRate)
            Log.replay.info("playback engine was stopped; rebuilt")
        } catch {
            Log.replay.error("playback engine rebuild failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func stopEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.stop()
        engine = nil
    }

    private func makeEngine(sampleRate: Double) throws {
        stopEngine()
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CaptureError.noFormat
        }
        let source = AVAudioSourceNode(format: format) { [state] _, _, frameCount, data -> OSStatus in
            let out = UnsafeMutableAudioBufferListPointer(data)
            guard let dst = out.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            dst.initialize(repeating: 0, count: frames)
            _ = state.withLockIfAvailable { s in
                let range = s.transport.advance(frames: frames)
                s.clip.withUnsafeBufferPointer { src in
                    guard let base = src.baseAddress, !range.isEmpty else { return }
                    dst.update(from: base + range.lowerBound, count: range.count)
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
        // A new output device (AirPods connecting, a different rate) stops the engine: rebuild it on the same
        // transport, so the replay carries on where it was.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self, weak engine] _ in
            guard let self, let engine, engine === self.engine, !engine.isRunning else { return }
            do {
                try self.makeEngine(sampleRate: self.engineRate)
                Log.replay.info("output changed; playback engine rebuilt")
            } catch {
                Log.replay.error("output changed; rebuild failed: \(String(describing: error), privacy: .public)")
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        engineRate = sampleRate
    }
}
