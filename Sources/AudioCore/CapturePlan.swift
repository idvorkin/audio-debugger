/// Story 017/018: what M is about to capture, chosen in the capture picker: which mics (a switch each), at once or in
/// turn, and for how long. USB and built-in mics start on; Bluetooth and Continuity mics start off, each with the
/// reason (`risk`), since opening one changes something outside the app. The last choice is remembered.
public struct CapturePlan: Equatable, Sendable {
    public static let secondsRange: ClosedRange<Double> = 2...15  // under the 20 s capture ring

    public let mics: [Mic]
    public private(set) var chosen: Set<String>
    public private(set) var mode: CaptureSet.Mode
    public private(set) var seconds: Double

    /// `remembered`: the mics (UIDs) chosen last time; those still plugged in start on. None of them present (or no
    /// memory): every mic that opens without side effects.
    public init(mics: [Mic], remembered: Set<String>?, mode: CaptureSet.Mode, seconds: Double? = nil) {
        self.mics = mics
        self.mode = mode
        self.seconds = Self.clamp(seconds ?? Self.defaultSeconds(mode))
        let present = (remembered ?? []).intersection(mics.map(\.uid))
        chosen = present.isEmpty ? Set(mics.filter { Self.risk($0) == nil }.map(\.uid)) : present
    }

    /// The chosen mics, in list order.
    public var selected: [Mic] { mics.filter { chosen.contains($0.uid) } }

    public func isOn(_ mic: Mic) -> Bool { chosen.contains(mic.uid) }

    /// 1–9: switch mic `index` (0-based) on or off.
    public mutating func toggle(_ index: Int) {
        guard mics.indices.contains(index) else { return }
        let uid = mics[index].uid
        if chosen.contains(uid) { chosen.remove(uid) } else { chosen.insert(uid) }
    }

    /// T: at once ⇄ in turn.
    public mutating func toggleMode() { mode = mode == .together ? .inTurn : .together }

    /// ← / →: a second shorter or longer, within `secondsRange`.
    public mutating func adjust(by delta: Double) { seconds = Self.clamp((seconds + delta).rounded()) }

    public mutating func setSeconds(_ value: Double) { seconds = Self.clamp(value.rounded()) }

    /// Why a mic starts off: opening it changes something outside the app.
    public static func risk(_ mic: Mic) -> String? {
        switch mic.kind {
        case .bluetooth: "opening it puts the headset in call mode: its music drops to phone quality"
        case .continuity: "opening it wakes the iPhone and takes its mic"
        default: nil
        }
    }

    public static func defaultSeconds(_ mode: CaptureSet.Mode) -> Double { mode == .together ? 10 : 6 }

    private static func clamp(_ s: Double) -> Double { min(max(s, secondsRange.lowerBound), secondsRange.upperBound) }
}
