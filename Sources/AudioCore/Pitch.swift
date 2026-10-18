import Accelerate

/// Autocorrelation pitch over 60–1000 Hz, computed by FFT. Returns 0 when the block is silent or unvoiced.
public final class PitchDetector: @unchecked Sendable {
    public let size: Int
    public let sampleRate: Float
    private let fft: RealFFT

    public init(size: Int, sampleRate: Float) {
        self.size = size
        self.sampleRate = sampleRate
        fft = RealFFT(n: 2 * size)  // zero-padded so the autocorrelation does not wrap
    }

    public func pitch(_ block: [Float]) -> Float {
        precondition(block.count == size)
        let mean = vDSP.mean(block)
        let x = vDSP.add(-mean, block)
        // -60 dBFS gate: quiet mics still read, silence does not.
        guard rms(x[...]) >= 0.001 else { return 0 }
        let (re, im) = fft.forward(x + [Float](repeating: 0, count: size))
        // Power spectrum in the packed layout: DC² in real[0], Nyquist² in imag[0].
        var power = vDSP.add(vDSP.square(re), vDSP.square(im))
        power[0] = re[0] * re[0]
        var zero = [Float](repeating: 0, count: re.count)
        zero[0] = im[0] * im[0]
        let corr = Array(fft.inverse(real: power, imag: zero).prefix(size))
        guard corr[0] > 0 else { return 0 }
        let lo = max(1, Int((sampleRate / 1000).rounded(.up)))
        let hi = min(Int(sampleRate / 60), size - 2)
        guard hi >= lo else { return 0 }
        // The strongest local maximum, not the descending edge of the zero-lag lobe.
        var best = -1
        for lag in lo...hi where corr[lag] >= corr[lag - 1] && corr[lag] >= corr[lag + 1] {
            if best < 0 || corr[lag] > corr[best] { best = lag }
        }
        guard best > 0, corr[best] > 0.3 * corr[0] else { return 0 }
        return sampleRate / Float(best)
    }
}
