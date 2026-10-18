import Accelerate

/// Scale so the loudest sample sits at -1 dBFS. Silence comes back unchanged.
public func normalizePeak(_ x: [Float]) -> [Float] {
    let p = peak(x[...])
    return p > 0 ? vDSP.multiply(0.89 / p, x) : x
}

/// One RBJ-cookbook biquad section (Butterworth Q), direct form I.
struct Biquad {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    static func highPass(_ f: Float, rate: Float) -> Biquad { make(f, rate: rate, high: true) }
    static func lowPass(_ f: Float, rate: Float) -> Biquad { make(f, rate: rate, high: false) }

    private static func make(_ f: Float, rate: Float, high: Bool) -> Biquad {
        let w = 2 * Float.pi * f / rate
        let alpha = sin(w) / (2 * 0.707_107)
        let c = cos(w)
        let a0 = 1 + alpha
        let b1 = high ? -(1 + c) : 1 - c
        let b0 = high ? (1 + c) / 2 : (1 - c) / 2
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b0 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    func apply(_ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in x.indices {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }
}

/// Voice boost: band-limit to 90 Hz–7.5 kHz (4th order each side), bring the loud frames (the speech, not the
/// silences between) to `targetDB` RMS, then soft-limit with tanh so peaks round off instead of clipping.
public func voiceBoost(_ x: [Float], sampleRate: Float, targetDB: Float = -16) -> [Float] {
    let hp = Biquad.highPass(90, rate: sampleRate)
    let lp = Biquad.lowPass(min(7500, sampleRate / 2 - 1), rate: sampleRate)
    let y = lp.apply(lp.apply(hp.apply(hp.apply(x))))
    let frame = max(1, Int(sampleRate) / 50)  // 20 ms
    let frames = y.count / frame
    guard frames > 0 else { return y }
    let loudness = (0..<frames).map { rms(y[$0 * frame..<($0 + 1) * frame]) }.sorted()
    let loud = loudness[min(frames - 1, Int(Float(frames) * 0.9))]
    guard loud > 0 else { return y }
    let gain = pow(10, targetDB / 20) / loud
    let drive: Float = 1.2
    return y.map { tanh($0 * gain * drive) / drive }  // unity gain for small signals, peaks under 1/drive
}

/// Spectral-gating noise reduction. The noise profile (per-bin mean + 1.5σ in dB) comes from the quietest 20% of
/// STFT frames: profiling the whole clip would count sustained voice as noise and gate it away. Bins under the
/// threshold are turned down by `reduction` (0.9 = -20 dB); the mask is smoothed over 3 frames × 3 bins to avoid
/// "musical noise".
public func denoise(_ x: [Float], reduction: Float = 0.9, frameSize: Int = 2048) -> [Float] {
    let hop = frameSize / 4
    guard x.count >= frameSize * 2 else { return x }
    let fft = RealFFT(n: frameSize)
    let window = hannWindow(frameSize)
    let bins = frameSize / 2 + 1
    let padded = [Float](repeating: 0, count: frameSize) + x + [Float](repeating: 0, count: frameSize)
    let starts = Array(stride(from: 0, through: padded.count - frameSize, by: hop))

    var spectra: [(re: [Float], im: [Float])] = []
    var mags: [[Float]] = []
    var energy: [Float] = []
    spectra.reserveCapacity(starts.count)
    for s in starts {
        let raw = Array(padded[s..<s + frameSize])
        energy.append(rms(raw[...]))
        let (re, im) = fft.forward(vDSP.multiply(raw, window))
        spectra.append((re, im))
        var m = [Float](repeating: 0, count: bins)
        m[0] = abs(re[0])
        m[bins - 1] = abs(im[0])
        for k in 1..<frameSize / 2 { m[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot() }
        mags.append(m.map { max(decibels($0), -140) })  // clamp: exact zeros would skew the profile
    }

    // Noise profile from the quietest frames, among those wholly inside the clip: the zero padding (or any digital
    // silence) would put -200 dB readings in the profile, blow up its σ and lift the threshold over the voice.
    let inside = starts.indices.filter { starts[$0] >= frameSize && starts[$0] + frameSize <= frameSize + x.count }
    let candidates = inside.isEmpty ? Array(starts.indices) : inside
    let quietCount = max(1, candidates.count / 5)
    let quiet = candidates.sorted { energy[$0] < energy[$1] }.prefix(quietCount)
    var threshold = [Float](repeating: 0, count: bins)
    for k in 0..<bins {
        let v = quiet.map { mags[$0][k] }
        let mean = v.reduce(0, +) / Float(v.count)
        let sd = (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(v.count)).squareRoot()
        threshold[k] = mean + 1.5 * sd
    }

    let floorGain = 1 - reduction
    let rawMask = mags.map { m in (0..<bins).map { m[$0] > threshold[$0] ? Float(1) : floorGain } }

    var out = [Float](repeating: 0, count: padded.count)
    var weight = [Float](repeating: 0, count: padded.count)
    let window2 = vDSP.square(window)
    for (f, s) in starts.enumerated() {
        var mask = [Float](repeating: 0, count: bins)
        for k in 0..<bins {
            var sum: Float = 0, n: Float = 0
            for df in -1...1 where f + df >= 0 && f + df < rawMask.count {
                for dk in -1...1 where k + dk >= 0 && k + dk < bins {
                    sum += rawMask[f + df][k + dk]
                    n += 1
                }
            }
            mask[k] = sum / n
        }
        var (re, im) = spectra[f]
        re[0] *= mask[0]
        im[0] *= mask[bins - 1]
        for k in 1..<frameSize / 2 {
            re[k] *= mask[k]
            im[k] *= mask[k]
        }
        let frame = vDSP.multiply(fft.inverse(real: re, imag: im), window)
        for i in 0..<frameSize {
            out[s + i] += frame[i]
            weight[s + i] += window2[i]
        }
    }
    return (0..<x.count).map { i in
        let w = weight[i + frameSize]
        return w > 1e-6 ? out[i + frameSize] / w : 0
    }
}

/// Min and max of each of `buckets` equal slices, for drawing a long clip as a filled envelope.
public func envelope(_ x: [Float], buckets: Int) -> [(min: Float, max: Float)] {
    guard !x.isEmpty, buckets > 0 else { return [] }
    let n = min(buckets, x.count)
    return (0..<n).map { b in
        let slice = x[b * x.count / n..<max(b * x.count / n + 1, (b + 1) * x.count / n)]
        return (slice.min() ?? 0, slice.max() ?? 0)
    }
}
