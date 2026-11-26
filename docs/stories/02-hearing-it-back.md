# Hearing it back

## 003 — Replay the last 20, 10 or 5 seconds

**Summary**: The last 20 s are always kept; one key plays the last 20, 10 or 5 s, with the clip's waveform, a
playhead and a scrubber.
**Status**: Done (06c69ad, cb62d8a plays at once and survives an output change; host tests for the ring and
transport; selftest: open, pause holds, seek; by ear: ad-dsc)
**Why**: "Can I always replay the last 20 seconds?"; "replay should have 20, 10, 5 s and bring up a playback bar
and waveform".

**Use Case**: As Igor, I want to hear what I just said without having pressed record, so that I know how I sound.

**Acceptance Criteria**

- Scenario: Replay without recording
  - Given the app has been open for a minute
  - When I press R
  - Then the last 20 s play in both ears, and the replay panel shows their waveform with a moving playhead
- Scenario: Young buffer
  - Given the app opened 4 s ago
  - When I press R
  - Then the 4 s captured so far play

## 004 — Pause, replay and scrub

**Summary**: Space pauses and resumes; A starts over; the scrubber, a click or drag on the waveform, and the arrow
keys seek.
**Status**: Done (06c69ad; host test for the transport; selftest: pause holds, seek to the middle, restart)
**Why**: "When replay I should have pause, replay, and a scrubber bar".

**Use Case**: As Igor, I want to stop and go back to one word, so that I can listen to it again.

**Acceptance Criteria**

- Scenario: Pause holds the place
  - Given a replay is playing at 3.2 s
  - When I press Space
  - Then it stops at 3.2 s, and Space again resumes from there
- Scenario: Play from the end starts over
  - Given the replay reached its end
  - When I press Space
  - Then it plays from the start
- Scenario: Scrub
  - Given a replay is open
  - When I click at the middle of its waveform
  - Then playback continues from the middle

## 005 — Noise reduction and voice boost

**Summary**: Replay is cleaned up by default: spectral-gating noise reduction and a voice boost; N and B toggle each,
live, keeping the place, to compare.
**Status**: Done (06c69ad, cb62d8a brief speech and dropouts; host tests: voice over hiss improves by more than
15 dB, one second of speech in twenty levelled to target; selftest: both toggles, place kept, 20 ms for 5 s)
**Why**: "Let's boost voice and apply some noise cancellation algos on replay as well".

**Use Case**: As Igor, I want a quiet, hissy mic to sound like my voice on replay, so that I can judge the words and
not the hiss.

**Acceptance Criteria**

- Scenario: Quiet mic, clean replay
  - Given my mic records speech at -47 dBFS RMS over a -55 dBFS hiss
  - When I replay with both on
  - Then speech plays at about -16 dBFS RMS and the hiss between words is at least 15 dB under it
- Scenario: Compare
  - Given a replay is playing at 2.0 s
  - When I press N
  - Then the clip switches to the one without noise reduction and keeps playing from 2.0 s

**Notes**: The noise profile comes from the quietest 20 % of frames inside the clip; profiling the whole clip
counted sustained voice as noise and removed it (found by the host test). Each combination is computed once per
replay, off the main thread. Without either, the clip is normalized to -1 dBFS peak.

## 013 — Save a sample with its measurements

**Summary**: S saves the last 20 s the mic heard, raw, as a WAV with a JSON sidecar of what was measured: noise
floor, median, speech level, separation and its band, peak, clipped samples, mic, rate, commit.
**Status**: In progress (9680129; the sidecar's maths: host tests on Linux, and run over a 60 s 16 kHz
recording: floor -61.7, speech -16.2, separation 45.5 dB GOOD; the app layer cross-compiled for macOS. On the Mac,
2026-11-24, the selftest saved `sample.wav` (48 kHz mono float32) and `sample.json` with numbers in tenths. Later
that day the selftest on AirPods (24 kHz) wrote `"seconds" : 17.940000000000001` for a clip under 20 s; seconds now
print in hundredths (host test `sidecarNumbersPrintShort`, then the selftest on AirPods wrote `13.94`). S revealing
the WAV in Finder owed to a run)
**Why**: "So I could take my live samples and maybe save them": a room or a mic, kept to compare later.

**Use Case**: As Igor, I want to keep the last 20 seconds with its numbers, so that I can compare mics and rooms
later, or hand the clip to another tool.

**Acceptance Criteria**

- Scenario: Save
  - Given the app has heard 20 s of me talking
  - When I press S
  - Then `samples/<yyyyMMdd-HHmmss>/sample.wav` and `sample.json` appear under the app's folder, Finder shows the
    WAV, and the status line says "saved samples/<time>" for a few seconds
- Scenario: The sidecar matches the file
  - Given a saved sample
  - When I read `sample.json`
  - Then its floor, speech and separation are those of the raw WAV beside it, in 50 ms frames, not the live readout
    and not the replay's processed audio
  - And decibels read in tenths and the length in hundredths of a second (`-69.4`, `17.94`), never 17 digits
- Scenario: Never filed as a bug
  - Given the bug-kit listener reads the app's folder
  - When I save a sample
  - Then nothing is written under `bugs/`, so no bead is filed

**Notes**: The folder is `SessionLog.root` (`~/Library/Application Support/AudioDebugger/` on the Mac, the app's
Documents on iOS; `selftest/` inside it for scripted runs). On iOS the folder is not yet visible in the Files app.
Nothing is uploaded.
