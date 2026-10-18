# Hearing it back

## 003 — Replay the last 20, 10 or 5 seconds

**Summary**: The last 20 s are always kept; one key plays the last 20, 10 or 5 s, with the clip's waveform, a
playhead and a scrubber.
**Status**: Done (initial commit; host tests for the ring and transport; selftest: open, pause holds, seek)
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
**Status**: Done (initial commit; host test for the transport; selftest: pause holds, seek to the middle, restart)
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
**Status**: Done (initial commit; host test: voice over hiss improves by more than 15 dB; selftest: both toggles,
place kept, 20 ms for 5 s)
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
