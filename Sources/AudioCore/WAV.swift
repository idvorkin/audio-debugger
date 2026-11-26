import Foundation

/// Story 019: WAV files without AVFoundation, so a capture set loads, and its tests run, in plain Swift. Reads mono or
/// the first channel of 32-bit float (format 3, or extensible with a float subformat, as `AVAudioFile` writes) and
/// 16-bit PCM; writes mono 32-bit float.
public enum WAV {
    public enum Problem: Error, CustomStringConvertible, Equatable {
        case notWAV, noFormat, noData, unsupported(format: Int, bits: Int)

        public var description: String {
            switch self {
            case .notWAV: "not a WAV file"
            case .noFormat: "the WAV file has no format chunk"
            case .noData: "the WAV file has no audio data"
            case .unsupported(let format, let bits): "unsupported WAV encoding (format \(format), \(bits) bit)"
            }
        }
    }

    public static func decode(_ data: Data) throws -> (samples: [Float], rate: Double) {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        func tag(_ i: Int) -> String { String(decoding: bytes[i..<(i + 4)], as: UTF8.self) }
        guard bytes.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else { throw Problem.notWAV }
        var format = 0, channels = 1, rate = 0, bits = 0
        var dataRange: Range<Int>?
        var i = 12
        while i + 8 <= bytes.count {
            let id = tag(i), size = u32(i + 4), body = i + 8
            let end = min(bytes.count, body + size)
            if id == "fmt " && size >= 16 && body + 16 <= bytes.count {  // a truncated file throws, never traps
                format = u16(body)
                channels = max(1, u16(body + 2))
                rate = u32(body + 4)
                bits = u16(body + 14)
                // WAVE_FORMAT_EXTENSIBLE: the real format is the subformat GUID's first two bytes.
                if format == 0xFFFE && size >= 26 && body + 26 <= bytes.count { format = u16(body + 24) }
            } else if id == "data" {
                dataRange = body..<end
            }
            i = body + size + (size & 1)
        }
        guard rate > 0 else { throw Problem.noFormat }
        guard let range = dataRange else { throw Problem.noData }
        let frameBytes = channels * bits / 8
        guard frameBytes > 0 else { throw Problem.unsupported(format: format, bits: bits) }
        let frames = range.count / frameBytes
        var samples = [Float](repeating: 0, count: frames)
        switch (format, bits) {
        case (3, 32):
            for f in 0..<frames {
                samples[f] = Float(bitPattern: UInt32(u32(range.lowerBound + f * frameBytes)))
            }
        case (1, 16):
            for f in 0..<frames {
                samples[f] = Float(Int16(bitPattern: UInt16(u16(range.lowerBound + f * frameBytes)))) / 32768
            }
        default:
            throw Problem.unsupported(format: format, bits: bits)
        }
        return (samples, Double(rate))
    }

    public static func encode(_ samples: [Float], rate: Double) -> Data {
        var out = Data()
        func put32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { out.append(contentsOf: $0) } }
        func put16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { out.append(contentsOf: $0) } }
        let dataSize = samples.count * 4
        out.append(contentsOf: Array("RIFF".utf8))
        put32(4 + 24 + 8 + dataSize)
        out.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16)
        put16(3)
        put16(1)
        put32(Int(rate))
        put32(Int(rate) * 4)
        put16(4)
        put16(32)
        out.append(contentsOf: Array("data".utf8))
        put32(dataSize)
        for s in samples { put32(Int(s.bitPattern)) }
        return out
    }
}
