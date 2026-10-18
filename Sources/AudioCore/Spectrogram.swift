/// A scrolling spectrogram as an RGBA pixel grid: one column per frame, newest on the right, low frequencies at the
/// bottom, coloured by an inferno-like map over [floorDB, ceilingDB].
public struct Spectrogram: Sendable {
    public let width: Int
    public let height: Int
    public let floorDB: Float
    public let ceilingDB: Float
    /// Row-major RGBA, top row first (what CGImage expects).
    public private(set) var pixels: [UInt32]

    public init(width: Int, height: Int, floorDB: Float = -100, ceilingDB: Float = -20) {
        self.width = width
        self.height = height
        self.floorDB = floorDB
        self.ceilingDB = ceilingDB
        pixels = [UInt32](repeating: Self.lut[0], count: width * height)
    }

    /// Scroll left one column and paint `column` (bin 0 = lowest frequency; resampled to `height` rows).
    public mutating func push(_ column: [Float]) {
        guard !column.isEmpty else { return }
        for row in 0..<height {
            let base = row * width
            pixels.withUnsafeMutableBufferPointer { p in
                guard let b = p.baseAddress else { return }
                (b + base).update(from: b + base + 1, count: width - 1)
            }
            let bin = (height - 1 - row) * column.count / height
            let t = (column[bin] - floorDB) / (ceilingDB - floorDB)
            pixels[base + width - 1] = Self.lut[Int(max(0, min(1, t)) * 255)]
        }
    }

    public mutating func clear() { pixels = [UInt32](repeating: Self.lut[0], count: width * height) }

    /// 256 colours along inferno's key points, packed RGBA (little-endian: 0xAABBGGRR).
    public static let lut: [UInt32] = {
        let keys: [(Float, Float, Float)] = [
            (0, 0, 4), (40, 11, 84), (101, 21, 110), (159, 42, 99), (212, 72, 66), (245, 125, 21),
            (250, 193, 39), (252, 255, 164),
        ]
        return (0..<256).map { i in
            let x = Float(i) / 255 * Float(keys.count - 1)
            let k = min(Int(x), keys.count - 2)
            let f = x - Float(k)
            let (r0, g0, b0) = keys[k], (r1, g1, b1) = keys[k + 1]
            let r = UInt32(r0 + (r1 - r0) * f), g = UInt32(g0 + (g1 - g0) * f), b = UInt32(b0 + (b1 - b0) * f)
            return 0xFF00_0000 | b << 16 | g << 8 | r
        }
    }()
}
