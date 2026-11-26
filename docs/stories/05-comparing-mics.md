# Comparing mics

Mac only. Design: [docs/specs/2026-11-26-compare-mics.md](../specs/2026-11-26-compare-mics.md).

## 017 — Capture every mic at once

**Summary**: M records the mics chosen in its picker (story 021; Bluetooth and iPhone mics start off) at the same
time for 10 s, into one capture set: a folder with each mic's raw WAV, its measurements, and a manifest that lines the
streams up.
**Status**: Built in e845c84 (ad-ppq; host tests for the manifest, offsets, mic filter and score; a failed or
silent mic left out of the offsets in 70bdc6b, host test). Selftest: a 2 s set of the built-in mic alone. Several mics at once, and AirPods left alone: to verify by Igor (run).
**Why**: "we will probably do the capture of all the streams. Then we can load them all and get some kind of view
debugger to see the difference" (Igor, 2026-11-26).

**Use Case**: As Igor, I want to record the same moment through every mic on the Mac, so that I can compare them on
the same sound later.

**Acceptance Criteria**

- Scenario: Every mic, the same span
  - Given the built-in mic and a USB mic are connected
  - When I press M and talk for 10 s
  - Then a capture set holds a WAV from each, covering the same 10 s, and the manifest gives each one's offset
- Scenario: A slow mic does not shorten the others
  - Given one mic takes 3 s to open
  - When I press M
  - Then the 10 s start once it has opened, so no row is shorter
- Scenario: AirPods are left alone
  - Given AirPods are connected and playing music
  - When I press M and Return, leaving the AirPods switch off
  - Then the AirPods mic is not opened and the music keeps its quality
- Scenario: A mic that fails is recorded, not fatal
  - Given a mic that will not open
  - When I press M
  - Then the set is still saved, and the manifest names that mic with the reason in words

## 018 — Capture every mic in turn

**Summary**: ⇧M (or T in the picker) records the chosen mics in turn, Bluetooth and iPhone mics included when switched
on, for 6 s each, with the same phrase to say on screen, into the same kind of capture set.
**Status**: Built in e845c84 (ad-ppq). Selftest: a 2 s turn of the built-in mic. Bluetooth and iPhone turns, and
Esc mid-run: to verify by Igor (run).
**Why**: "1 after other is interesting idea on osx" (Igor, 2026-11-26): for mics that can't run together, and to
compare the same words.

**Use Case**: As Igor, I want every mic to hear me say the same phrase, one after another, so that I can compare mics
that can't record together.

**Acceptance Criteria**

- Scenario: The same phrase on each mic
  - Given three mics are connected
  - When I press ⇧M
  - Then each opens in turn, the phrase and a countdown show, and the set holds three 6 s takes
- Scenario: Esc stops the run
  - Given a run in turn is on its second mic
  - When I press Esc
  - Then that mic closes, and the takes so far are saved as the set

## 019 — Compare a capture set

**Summary**: A viewer loads a capture set, just taken or earlier (⌘O), and ranks the mics best to worst with a
0–100 score and the numbers behind it, aligned waveforms and spectra, and one key per mic to listen (as recorded)
and A/B.
**Status**: Built in 9737f0c (ad-ppq). Host test: a four-stream fixture set loads, ranks, aligns and maps A/B places.
Selftest: the one-mic set just taken opens, 1 plays it raw, Esc Esc closes. Three mics, ⇥ by ear and ⌘O: to verify
by Igor (run).
**Why**: "comparison views... pick the best and the worst" (Igor, 2026-11-26).

**Use Case**: As Igor, I want the mics side by side with a ranking, so that I can pick the best and see why the worst
is worst.

**Acceptance Criteria**

- Scenario: Ranked with reasons
  - Given a capture set of three mics
  - When it opens
  - Then the rows run best to worst, each with its score, SNR, score floor, clipping, dropouts and bandwidth
- Scenario: Hear the difference
  - Given the viewer is open
  - When I press 2, then ⇥
  - Then row 2 plays in the replay panel, and ⇥ switches to the row played before at the same place
- Scenario: An old set
  - Given a capture set from last week
  - When I press ⌘O and choose it
  - Then it opens the same way, from the files alone

## 021 — Pick which mics to capture

**Summary**: M (and ⇧M) opens a picker in the main window: a switch per mic, at once or in turn, and a seconds
slider. USB and built-in mics start on; Bluetooth and iPhone mics start off, each saying what opening it would do. The
choice is remembered. Keys: 1–9 switch a mic, T at once / in turn, ← / → seconds, Return starts, Esc cancels.
**Status**: Planned (ad-ppq follow-up)
**Why**: "why didn't m cover the other ones? … pop up something asking me, or an option with sliders to pick which
ones to capture from maybe with switches" (Igor, 2026-11-26).

**Use Case**: As Igor, I want to choose which mics go into a capture set, so that I can include AirPods or an iPhone
when I mean to, and never by accident.

**Acceptance Criteria**

- Scenario: Safe mics on, risky ones off
  - Given the built-in mic, AirPods and an iPhone are listed
  - When I press M
  - Then the built-in mic's switch is on, the AirPods' and the iPhone's are off, each with what opening it would do
- Scenario: Include the AirPods
  - Given the picker is up
  - When I press the AirPods' number, then Return
  - Then the set is taken from the built-in mic and the AirPods together
- Scenario: Remembered
  - Given I took a set with the AirPods on
  - When I press M again
  - Then the AirPods' switch starts on
- Scenario: Cancel
  - Given the picker is up
  - When I press Esc
  - Then the picker closes and no mic is opened
