import Foundation

/// The mic open, fallback and retry chain, as a value. AppModel tells it what happened (the device list changed, a
/// pick, an open's result, a capture failure, the retry timer), with the time, and carries out the effects it returns
/// against `Capture` and the main queue. It has no clock, queue or device API of its own, so host tests drive every
/// case deterministically.
///
/// `mic` is only ever an open mic. Opens are numbered: a newer open supersedes an older one, whose result is dropped,
/// as the capture queue has already moved on to the newer mic.
public struct MicController: Sendable {
    public enum Effect: Equatable, Sendable {
        /// Close the open mic and open this one; report its result to `opened` or `failedToOpen` with `generation`.
        case open(Mic, generation: Int)
        /// Close the open mic.
        case stop
        /// Call `retryFired` after this many seconds. Only one is ever pending.
        case scheduleRetry(after: Double)
        /// Cancel the pending retry: a mic opened by another way, and the retry would reopen the healthy mic.
        case cancelRetry
        /// The mic opened at `rate`, `ms` after it was asked for: new analysers for the rate, readings reset.
        case didOpen(Mic, rate: Double, ms: Int)
        /// The mic would not open, `ms` after it was asked for.
        case didFail(Mic, error: String, ms: Int)
        /// Capture failed while another mic opens, which closes the failing one first; that open goes on.
        case failedWhileOpening
        /// Capture failed within 2 s of a reopen; a retry comes after `wait` s.
        case failedTooSoon(wait: Double)
        /// Capture failed; reopening the mic.
        case reopening
    }

    /// How a fallback chain ends.
    private enum Then: Sendable {
        /// Retry in 3 s if no mic opened.
        case retry
        /// Put back the picked mic's error (the user is told why the pick did not stick), then as `retry`.
        case sayWhy(String?)
    }

    /// What the newest open's result leads to.
    private enum Next: Sendable {
        /// On failure, the next best that has not failed this round.
        case best(wanted: String?, then: Then)
        /// The user's pick: on failure, the best of the rest, saying why.
        case picked
    }

    public private(set) var mics: [Mic] = []
    public private(set) var mic: Mic?
    public private(set) var error: String?
    /// The mic being opened on the capture queue; only the newest open's result counts.
    public private(set) var opening: Mic?
    public private(set) var retryPending = false

    /// `--mic NAME`: open the first mic whose name contains NAME, over the remembered one.
    private let micName: String?
    /// Mics that failed to open since the device list last changed: skipped when falling back.
    private var failed: Set<String> = []
    private var generation = 0
    private var next = Next.picked
    private var asked = Date.distantPast
    private var lastReopen = Date.distantPast

    public init(micName: String?) {
        self.micName = micName
    }

    /// The microphone permission was refused: say so. No open is tried until the device list next changes with the
    /// permission granted.
    public mutating func accessDenied(_ message: String) {
        error = message
    }

    /// The device list changed (or first load): reopen the wanted mic when it is back, fall back when it left.
    /// `remembered` is the mic the user last picked.
    public mutating func devicesChanged(_ list: [Mic], authorized: Bool, remembered: String?, now: Date) -> [Effect] {
        mics = list
        failed = []  // a device change is a new chance for every mic
        // Without the permission every mic fails, and those errors and retries would hide "Microphone access denied".
        guard authorized else { return [] }
        let named = micName.flatMap { n in mics.first { $0.name.localizedCaseInsensitiveContains(n) }?.uid }
        let wanted = named ?? remembered
        // The mic being opened counts as the current one: reopening it would only add another wait and gap.
        if let current = opening ?? mic, current.uid == Mic.choose(from: mics, wanted: wanted)?.uid,
            mics.contains(current)
        {
            return []
        }
        // Retries too: this chain may supersede captureFailed's, whose retry would then never run.
        var effects: [Effect] = []
        openBest(wanted: wanted, then: .retry, now: now, into: &effects)
        return effects
    }

    /// The user picked a mic (the caller remembers it, so it comes back by itself after being unplugged). If it will
    /// not open, fall back to the next best, and say why.
    public mutating func select(_ m: Mic, now: Date) -> [Effect] {
        // A second tap while it is still opening (taps queued behind the hang did this) would only open it again.
        guard opening != m else { return [] }
        failed.remove(m.uid)
        var effects: [Effect] = []
        open(m, next: .picked, now: now, into: &effects)
        return effects
    }

    /// The open numbered `generation` succeeded at `rate`.
    public mutating func opened(generation: Int, rate: Double, now: Date) -> [Effect] {
        guard generation == self.generation, let m = opening else { return [] }
        opening = nil
        mic = m
        error = nil
        var effects: [Effect] = []
        if retryPending {
            retryPending = false
            effects.append(.cancelRetry)
        }
        effects.append(.didOpen(m, rate: rate, ms: ms(since: asked, now)))
        if case .best(_, let then) = next { end(then, opened: true, into: &effects) }
        return effects
    }

    /// The open numbered `generation` failed with `error`.
    public mutating func failedToOpen(generation: Int, error message: String, now: Date) -> [Effect] {
        guard generation == self.generation, let m = opening else { return [] }
        opening = nil
        // Capture stopped the old session first, so nothing is open now.
        mic = nil
        failed.insert(m.uid)
        error = "\(m.name): \(message)"
        var effects: [Effect] = [.didFail(m, error: message, ms: ms(since: asked, now))]
        switch next {
        case .best(let wanted, let then):
            openBest(wanted: wanted, then: then, now: now, into: &effects)
        case .picked:
            openBest(wanted: nil, then: .sayWhy(error), now: now, into: &effects)
        }
        return effects
    }

    /// The running session failed (the device went away, a call took the mic): reopen, at most once per 2 s, and
    /// while that does not open any mic keep retrying every 3 s, so capture never stays stopped silently. `devices`
    /// reads the device list, only when a reopen goes ahead.
    public mutating func captureFailed(remembered: String?, now: Date, devices: () -> [Mic]) -> [Effect] {
        // A mic is being opened, which closes the failing one first: reopening the old mic here would undo the pick.
        guard opening == nil else { return [.failedWhileOpening] }
        let wait = 2 - now.timeIntervalSince(lastReopen)
        guard wait <= 0 else {
            error = "Capture failed; retrying in \(Int(wait.rounded(.up))) s"
            var effects: [Effect] = [.failedTooSoon(wait: wait)]
            retry(after: wait + 0.1, into: &effects)
            return effects
        }
        lastReopen = now
        var effects: [Effect] = [.reopening]
        let uid = mic?.uid ?? remembered
        mics = devices()
        failed = []  // each retry is a new chance for every mic: an interruption fails them all for a while
        openBest(wanted: uid, then: .retry, now: now, into: &effects)
        return effects
    }

    /// The pending retry's time came.
    public mutating func retryFired(remembered: String?, now: Date, devices: () -> [Mic]) -> [Effect] {
        retryPending = false
        return captureFailed(remembered: remembered, now: now, devices: devices)
    }

    // MARK: The chain

    /// Open the wanted mic, else the next best that has not failed this round.
    private mutating func openBest(wanted: String?, then: Then, now: Date, into effects: inout [Effect]) {
        guard let pick = Mic.choose(from: mics.filter { !failed.contains($0.uid) }, wanted: wanted) else {
            generation += 1  // an open still in flight is closed by this stop, so its result must not count
            opening = nil
            effects.append(.stop)
            mic = nil
            if error == nil { error = "No microphone found." }
            end(then, opened: false, into: &effects)
            return
        }
        open(pick, next: .best(wanted: wanted, then: then), now: now, into: &effects)
    }

    private mutating func end(_ then: Then, opened: Bool, into effects: inout [Effect]) {
        if case .sayWhy(let why) = then { error = why }
        if !opened { retry(after: 3, into: &effects) }
    }

    /// One pending retry at a time: two failures together (an interruption and a route change) must not start two
    /// chains that retry forever.
    private mutating func retry(after seconds: Double, into effects: inout [Effect]) {
        guard !retryPending else { return }
        retryPending = true
        effects.append(.scheduleRetry(after: seconds))
    }

    private mutating func open(_ m: Mic, next: Next, now: Date, into effects: inout [Effect]) {
        generation += 1
        opening = m
        asked = now
        self.next = next
        effects.append(.open(m, generation: generation))
    }

    private func ms(since start: Date, _ now: Date) -> Int { Int(now.timeIntervalSince(start) * 1000) }
}
