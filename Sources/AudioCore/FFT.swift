import Accelerate

/// A real FFT of a fixed power-of-two size over vDSP's packed split-complex format: bin 0's real part holds DC and
/// its imaginary part holds Nyquist. Forward output is twice the textbook DFT; forward then inverse scales by 2n.
public final class RealFFT: @unchecked Sendable {
    public let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    public init(n: Int) {
        precondition(n >= 4 && n & (n - 1) == 0, "FFT size must be a power of two")
        self.n = n
        log2n = vDSP_Length(n.trailingZeroBitCount)
        guard let s = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { fatalError("vDSP FFT setup failed") }
        setup = s
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Forward transform of `x` (count n) into packed (real, imag), each n/2 long.
    public func forward(_ x: [Float]) -> (real: [Float], imag: [Float]) {
        precondition(x.count == n)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                guard let r = rp.baseAddress, let i = ip.baseAddress else { return }
                var split = DSPSplitComplex(realp: r, imagp: i)
                x.withUnsafeBufferPointer { xp in
                    guard let base = xp.baseAddress else { return }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        return (real, imag)
    }

    /// Inverse of packed (real, imag) back to n samples, scaled so inverse(forward(x)) == x.
    public func inverse(real: [Float], imag: [Float]) -> [Float] {
        var real = real, imag = imag
        var out = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                guard let r = rp.baseAddress, let i = ip.baseAddress else { return }
                var split = DSPSplitComplex(realp: r, imagp: i)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                out.withUnsafeMutableBufferPointer { op in
                    guard let o = op.baseAddress else { return }
                    o.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(n / 2))
                    }
                }
            }
        }
        return vDSP.multiply(1 / Float(2 * n), out)
    }
}

/// A Hann window, periodic (sums cleanly under overlap-add).
public func hannWindow(_ n: Int) -> [Float] {
    (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n)) }
}

/// Amplitude spectrum in dBFS: a full-scale sine centred on a bin reads 0 dB. Bins 1..<n/2 (DC and Nyquist dropped).
public final class SpectrumAnalyzer: @unchecked Sendable {
    public let size: Int
    public let sampleRate: Double
    private let fft: RealFFT
    private let window: [Float]
    private let windowSum: Float

    public init(size: Int, sampleRate: Double) {
        self.size = size
        self.sampleRate = sampleRate
        fft = RealFFT(n: size)
        window = hannWindow(size)
        windowSum = window.reduce(0, +)
    }

    /// The centre frequency of each returned bin.
    public var frequencies: [Float] { (1..<size / 2).map { Float(Double($0) * sampleRate / Double(size)) } }

    public func decibelSpectrum(_ x: [Float]) -> [Float] {
        let (re, im) = fft.forward(vDSP.multiply(x, window))
        // Packed forward output is 2·DFT; a sine of amplitude A peaks at |DFT| = A·Σw/2, so A = |packed|/Σw.
        return (1..<size / 2).map { k in decibels((re[k] * re[k] + im[k] * im[k]).squareRoot() / windowSum) }
    }
}
