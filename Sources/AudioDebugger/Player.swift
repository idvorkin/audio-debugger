import AVFoundation
import AudioCore
import os

/// The replay side: its own engine on the default output, pulling from a clip through `Transport` on the render
/// thread, so pause, seek and swapping in a processed clip are just state changes. Mono into the main mixer, which
/// feeds both ears.
final class Player {
    private struct State {
        var clip: [Float] = []
        var transport = Transport()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var engine: AVAudioEngine?
    private var engineRate: Double = 0
    var muted = false {
        didSet { engine?.mainMixerNode.outputVolume = muted ? 0 : 1 }
    }

    var transport: Transport { state.withLock { $0.transport } }

    /// Swap in a clip. `keepPlace` keeps position and play state (a processing toggle); otherwise start from the top.
    func load(_ clip: [Float], sampleRate: Double, keepPlace: Bool) throws {
        state.withLock { s in
            s.clip = clip
            if keepPlace {
                s.transport.load(length: clip.count)
            } else {
                s.transport = Transport(length: clip.count)
            }
        }
        if engine == nil || engineRate != sampleRate { try makeEngine(sampleRate: sampleRate) }
    }

    func play() { state.withLock { $0.transport.play() } }
    func togglePlay() { state.withLock { $0.transport.togglePlay() } }
    func restart() { state.withLock { $0.transport.restart() } }
    func seek(to sample: Int) { state.withLock { $0.transport.seek(to: sample) } }

    func close() {
        state.withLock { $0 = State() }
        engine?.stop()
        engine = nil
    }

    private func makeEngine(sampleRate: Double) throws {
        engine?.stop()
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CaptureError.noFormat
        }
        let source = AVAudioSourceNode(format: format) { [state] _, _, frameCount, data -> OSStatus in
            let out = UnsafeMutableAudioBufferListPointer(data)
            guard let dst = out.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            dst.initialize(repeating: 0, count: frames)
            state.withLock { s in
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
        engine.prepare()
        try engine.start()
        self.engine = engine
        engineRate = sampleRate
    }
}
