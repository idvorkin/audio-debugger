/// A bare key, as each platform names it: the Mac's `Keys` monitor and the iPad's hardware keyboard both land here.
enum BareKey: Equatable {
    case space, escape, left, right
    case character(String)
}

extension AppModel {
    /// The bare keys (stories 01, 02): true when one did something.
    func press(_ key: BareKey, shift: Bool) -> Bool {
        switch key {
        case .space: togglePlay()  // play/pause, or open the last 20 s
        case .escape: closeReplay()
        case .left: jump(seconds: shift ? -5 : -1)
        case .right: jump(seconds: shift ? 5 : 1)
        case .character(let raw):
            let c = raw.lowercased()
            if let n = Int(c), (1...9).contains(n) {
                select(index: n - 1)
                return true
            }
            switch c {
            case "r": replay(seconds: 20)
            case "t": replay(seconds: 10)
            case "f": replay(seconds: 5)
            case "a": restart()
            case "n": processing.noiseReduction.toggle()
            case "b": processing.voiceBoost.toggle()
            case "c": resetReadings()
            default: return false
            }
        }
        return true
    }
}
