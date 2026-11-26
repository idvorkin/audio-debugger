# Compare mics: capture sets and a comparison viewer (Mac)

Beads: ad-ppq (compare), ad-ejj (share a sample). Stories 017–019 in [05-comparing-mics.md](../stories/05-comparing-mics.md).

Igor's steer (2026-11-26): "we will probably do the capture of all the streams. Then we can load them all and get some
kind of view debugger to see the difference... comparison views... pick the best and the worst." Mac first; "1 after
other is interesting idea on osx". iOS compare is dropped for now.

So two pieces, two PRs:

1. **Capture** (PR 2a): record every mic to disk as one *capture set*.
2. **Viewer** (PR 2b): load a capture set, now or later, and compare the mics side by side.

The live view does not change.

## Which mics

| Mode | Key | Mics | Why |
|---|---|---|---|
| All at once (default) | M | every input except Bluetooth and Continuity (iPhone) | Opening AirPods drops them into call mode, music and all; opening an iPhone mic wakes the phone. Neither should happen by accident |
| In turn | ⇧M | every input, Bluetooth and Continuity included | One mic open at a time, the same phrase each time: for mics that can't run together, and for A/B listening |

`Mic.Kind` gains `.continuity` (Core Audio transport `ccwd`/`ccwl`, `kAudioDeviceTransportTypeContinuityCapture*`);
today those land in `.other`. `Mic.choose` keeps them after the built-in mic, as now.

Scripted runs (`--capture-set`) take a mic filter (`--capture-mics MacBook`): a substring of the mic name. Without
it a scripted run refuses to start, so a selftest can never open AirPods or wake a phone. Scripted sets go under
`selftest/`, like bug reports, so they are never mistaken for Igor's.

## Taking a set

**All at once.** One `Capture` per mic (each owns a ring buffer). Open them all, in parallel on their own queues. The
take starts only once every mic has opened or failed, so every row covers the same span: a Bluetooth mic can take
seconds. Then record `seconds` (default 10, at most 15, under the 20 s ring), take the newest `seconds` from each
ring, close them all. The live mic carries on throughout.

**In turn.** The same phrase on screen for each mic: open it, wait for it to open (or fail, recorded and skipped),
show "Say: …" with a countdown, record `seconds` (default 6), close it, next. The live mic carries on, as in all at
once. A failed open never stops the run.

**Alignment.** Each `Capture` notes when the newest buffer it took in arrived (`ProcessInfo.systemUptime`, seconds
since boot, one clock for every stream).
A stream's start is that time minus its length. In a set taken at once, each stream's `offset` is its start minus the
earliest start among the streams that recorded audio; a failed or silent stream has no start and an offset of 0. Arrival time includes each device's own latency, so this is an estimate, not yet measured: perhaps
a buffer or two (tens of ms). Good for seeing and hearing the difference, not for phase. `offset` is the viewer's only
alignment input, so a better estimate (cross-correlation, once Igor has a two-mic set) changes one number. In turn,
offsets are 0 and each stream keeps its own `started` time.

The phrase: "Six thick thistle sticks. A quick brown fox jumps over the lazy dog." Sibilants and plosives, to show
the band and the clipping.

## On disk

`~/Library/Application Support/AudioDebugger/captures/<yyyyMMdd-HHmmss>/` (outside `bugs/`, so the bug-kit listener
never files it; under `selftest/captures/` for scripted runs):

```
manifest.json
1-macbook-pro-microphone.wav     mono float32 at the mic's own rate, raw
1-macbook-pro-microphone.json    the sample sidecar (Sample.swift's: floor, speech, separation, peak, clips)
2-usbaudio1-0.wav
2-usbaudio1-0.json
```

`manifest.json`, version 1:

```json
{
  "version": 1,
  "created": "2026-11-26T20:40:38Z",
  "mode": "together",
  "seconds": 10,
  "phrase": "Six thick thistle sticks…",
  "commit": "da3bfb9",
  "streams": [
    {"index": 1, "name": "MacBook Pro Microphone", "uid": "BuiltInMicrophoneDevice", "kind": "builtIn",
     "rate": 48000, "file": "1-macbook-pro-microphone.wav", "offset": 0.012, "started": 1795725525.25,
     "openMs": 126},
    {"index": 2, "name": "Work iPhone igor Microphone", "uid": "…", "kind": "continuity",
     "error": "the mic is not available to capture (unplugged?)", "openMs": 3010}
  ]
}
```

`mode` is `together` or `inTurn`. A failed stream has `error` and no `file`. The `CaptureSet` type (AudioCore, no
Accelerate) encodes and decodes it, host-tested both ways, and rejects an unknown `version`.

## The score

A port of context-grabber's `MicSound` (`native/ContextCore/Sources/ContextCore/Call/MicSound.swift`), exactly:
100 ms pieces; the floor is the 10th percentile of the pieces' levels, speech the 90th, speech only when 6 dB over
the floor; SNR 50 points (30 dB full), floor 20 (−60 dBFS full, −30 none), clipping 15 (none full, 10 % of pieces
none), dropouts 15 (none full, 20 % none); no speech scales the other three to 100.

**One stream is one window**, not the median of 5 s windows: a 6–15 s take of a phrase is short, and splitting it
would score the pause between words on its own. The host test pins the port with vectors produced by running
Grabber's own `MicSound` (a recorded fixture, not hand-computed), so the two never drift.

The score's floor (100 ms pieces) is labelled **score floor**, apart from the live readout's noise floor (50 ms
frames over 20 s), so two different numbers never share a name.

Bandwidth: the mic's Nyquist (rate / 2), amber under 8 kHz (story 015's mark).

## The viewer (PR 2b)

Reads only files (AudioCore's `Comparison`, with a plain-Swift `WAV` reader): a capture set just taken, or an earlier
one (⌘O; the set just taken opens by itself). Mac only, its UI in `Mac/CompareView.swift`. It takes the live panels'
place in the main window (not a sheet: a sheet can't be screenshotted, and the window stays keyboard-driven); Esc or
⌘. closes it.

- One row per stream, **ranked best to worst** by score (recomputed from the WAV, so an old set scores as a new one);
  failed streams last, their error in selectable text.
- Per row: name, kind, score and its parts (SNR, score floor, clipped and dropout pieces), peak, rate and top
  frequency (amber under 8 kHz).
- Waveforms on one shared time axis (placed by `offset`), all at one gain (the loudest row's peak fills its lane), so
  a quieter mic looks quieter; and every row's long-term spectrum overlaid on one log-frequency chart.
- **Listen raw**: digits 1–9 play that row through the replay panel **as recorded**: no noise reduction, no boost, no
  normalizing, because those would erase the level and floor differences being compared. N / B are disabled while a
  row plays and the saved toggles are untouched. A digit carries the place over from the row playing, on the set's
  timeline (seconds plus offset, since rows differ in rate and start); **⇥** goes back to the row played before, at the
  same place, for A/B. Space with nothing playing plays the last row (or row 1).
- Reveal in Finder (⌘R). Sharing a set or a sample (`ShareLink`) is ad-ejj, a separate change; when it lands, sharing
  is only ever user-initiated.

Every viewer action has a key, in `KeyTable` and "Keys at a glance" together.

## Verification

- Host: `Mic` kind mapping, `CaptureSet` round trip, offsets, the score port against Grabber's vectors, ranking.
- Selftest: `--capture-set together --capture-mics MacBook` takes a one-mic set and checks the manifest and WAV; the
  log says so.
- **Limit**: on this Mac only the built-in mic can be opened by a script (the default input is AirPods; the others
  are iPhones). Capturing several mics at once is unproven until Igor runs it with the USB mic plugged in; each PR
  says so.
