# Hearing it back

## 003 — Replay the last 20, 10 or 5 seconds

**Summary**: The last 20 s are always kept; one key plays the last 5, 10 or 20 s (R, T, Y: left to right on the
keyboard, shortest first), with the clip's waveform, a playhead and a scrubber.
**Status**: Done (06c69ad, cb62d8a plays at once and survives an output change; host tests for the ring and
transport; selftest: open, pause holds, seek; by ear: ad-dsc). Keys R / T / Y for 5 / 10 / 20 s: built in
bcaa22a (ad-49f); host test for the key-to-seconds table, R and Y verified on `just selftest`.
**Why**: "Can I always replay the last 20 seconds?"; "replay should have 20, 10, 5 s and bring up a playback bar
and waveform"; "obvious replay keys" (Igor, 2026-11-25): R was 20 s and F 5 s, which nobody could guess.

**Use Case**: As Igor, I want to hear what I just said without having pressed record, so that I know how I sound.

**Acceptance Criteria**

- Scenario: Replay without recording
  - Given the app has been open for a minute
  - When I press Y
  - Then the last 20 s play in both ears, and the replay panel shows their waveform with a moving playhead
- Scenario: Shortest first
  - Given the app has been open for a minute
  - When I press R, then T
  - Then R plays the last 5 s and T the last 10 s
- Scenario: Young buffer
  - Given the app opened 4 s ago
  - When I press Y
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
the WAV in Finder owed to a run). Share and Reveal (ad-ejj) built in 0e16634: selftest logs Share handing over
`sample.wav sample.json`, both on disk; `just ios-build`. The share sheet itself, on the Mac and the iPhone: to
verify by Igor (run)
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
- Scenario: Share it (ad-ejj)
  - Given I saved a sample on the iPhone
  - When I tap Share sample
  - Then the system share sheet offers `sample.wav` and `sample.json` (AirDrop to the Mac, Messages, Files…)
- Scenario: Share or reveal on the Mac (ad-ejj)
  - Given I saved a sample, or a capture set is open (story 019)
  - When I press ⇧⌘S, or ⌘R
  - Then the share menu offers the set's folder, else the sample's two files; ⌘R shows them in Finder

**Notes**: The folder is `SessionLog.root` (`~/Library/Application Support/AudioDebugger/` on the Mac, the app's
Documents on iOS; `selftest/` inside it for scripted runs). On iOS the folder is not yet visible in the Files app, so
Share is the way off the phone. Nothing is uploaded: sharing happens only when Igor asks, through the system's own
share sheet.

## 020 — Choose the speakers apart from the mic

**Summary**: Replay plays on an output chosen apart from the mic: O steps through the outputs (the system default
first, then every speaker and headphone), the choice is remembered, and a line under the input line names it. An
unplugged choice falls back to the system default and comes back when it is plugged in again.
**Status**: Built in a57caac (ad-0er; host tests for the choice, fallback and stepping). Selftest: a muted replay on
the built-in speakers, O, and the remembered choice restored. Two real outputs, headphones by ear, and unplugging
the choice: to verify by Igor (run); this Mac had only its speakers.
**Why**: "audio debugger also lets select speakers independent of mic" (Igor, 2026-11-26): test the USB mic while
listening on the Mac's speakers, or the built-in mic on headphones, without changing the Mac's own output.

**Use Case**: As Igor, I want replay on the headphones I choose whatever mic is open, so that I can listen closely
without changing the Mac's sound settings.

**Acceptance Criteria**

- Scenario: Step to another output
  - Given the system output is the Mac's speakers and headphones are plugged in
  - When I press O until the output line names the headphones, then press R
  - Then the last 5 s play in the headphones, and the Mac's own output setting is unchanged
- Scenario: Remembered
  - Given I chose the headphones
  - When I quit and reopen the app
  - Then replay still plays in the headphones
- Scenario: Unplugged
  - Given I chose the headphones and they are unplugged
  - When I press R
  - Then the replay plays on the system default, the output line says the chosen output is missing, and it is used
    again once plugged back in

- Scenario: On the iPhone (ad-8ev)
  - Given AirPods are connected and the built-in mic is open
  - When I tap the route button on the output row and pick the AirPods
  - Then replay plays in the AirPods (full quality: their mic stays closed) and the row names them
- Scenario: A headset mic ties the output (ad-8ev)
  - Given the AirPods' mic is the open mic
  - When I look at the output row
  - Then it names the AirPods in amber and says the output is tied to the headset's mic

**Notes**: On the iPhone and iPad (ad-8ev) the output is the audio session's route, so the row under the input line
shows it and offers the system's own route picker (`AVRoutePickerView`): AirPods, AirPlay, a wired headset, the
speaker. There is no per-app device as on the Mac, so O does nothing there. With nothing plugged in, replay plays on
the speaker (`.defaultToSpeaker`); the earpiece is not offered, as switching to it would mean changing the session's
category under a running capture. iOS: built in 01132b3, `just ios-build` passes; the simulator selftest could not
run (other sessions' simulators were booted); on the phone: to verify by Igor.
