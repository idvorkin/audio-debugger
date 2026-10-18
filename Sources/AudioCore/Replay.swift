/// The always-on replay buffer: the last `capacity` samples, oldest overwritten first. Not thread-safe; the app
/// guards it with a lock shared by the audio thread and the main thread.
public struct RingBuffer: Sendable {
    public let capacity: Int
    private var storage: [Float]
    private var head = 0
    /// Samples ever written (so a young buffer knows how much of it is real).
    public private(set) var total = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    public mutating func write(_ samples: UnsafeBufferPointer<Float>) {
        for s in samples {
            storage[head] = s
            head = head == capacity - 1 ? 0 : head + 1
        }
        total += samples.count
    }

    public mutating func write(_ samples: [Float]) { samples.withUnsafeBufferPointer { write($0) } }

    /// The newest `count` samples (fewer while the buffer is younger than that), oldest first.
    public func last(_ count: Int) -> [Float] {
        let n = min(count, total, capacity)
        let start = (head - n + capacity) % capacity
        if start + n <= capacity { return Array(storage[start..<start + n]) }
        return Array(storage[start...]) + Array(storage[..<(start + n - capacity)])
    }

    public mutating func reset() {
        storage = [Float](repeating: 0, count: capacity)
        head = 0
        total = 0
    }
}

/// The replay transport: where playback is in a clip, and whether it runs. The audio thread calls `advance` once
/// per render; the UI calls the rest. Reaching the end pauses there; play from the end starts over.
public struct Transport: Sendable, Equatable {
    public private(set) var length: Int
    public private(set) var position = 0
    public private(set) var playing = false

    public init(length: Int = 0) { self.length = length }

    public var atEnd: Bool { position >= length }

    /// A new clip (a processing toggle swaps clips of the same length): keep the place, clamped.
    public mutating func load(length: Int) {
        self.length = length
        position = min(position, length)
    }

    public mutating func play() {
        if atEnd { position = 0 }
        playing = length > 0
    }

    public mutating func pause() { playing = false }

    public mutating func togglePlay() { if playing { pause() } else { play() } }

    public mutating func restart() {
        position = 0
        playing = length > 0
    }

    public mutating func seek(to sample: Int) { position = max(0, min(sample, length)) }

    /// Claim the next `frames` samples to render; empty when paused. Stops at the end of the clip.
    public mutating func advance(frames: Int) -> Range<Int> {
        guard playing else { return position..<position }
        let end = min(position + frames, length)
        let range = position..<end
        position = end
        if atEnd { playing = false }
        return range
    }
}
