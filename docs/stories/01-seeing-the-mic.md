# Seeing the mic

## 001 — Choose the mic

**Summary**: Every mic is a button; a number key switches; the choice is remembered and comes back when re-plugged.
**Status**: Done (initial commit; selftest: mic list and `--mic MacBook`; switching by key: run, Igor)
**Why**: "Mic selection is hard to change" (the Python app's dropdown).

**Use Case**: As Igor, I want to switch mics with one key, so that I can compare them while I talk.

**Acceptance Criteria**

- Scenario: Switch by key
  - Given the app shows mics numbered 1 to 5
  - When I press 3
  - Then the third mic opens and is highlighted, and the readings reset
- Scenario: The USB mic comes back
  - Given I chose the USB mic and it was unplugged, so the app fell back to the built-in mic
  - When the USB mic is plugged back in
  - Then the app reopens the USB mic by itself
- Scenario: Never AirPods by accident
  - Given no mic was chosen and no USB mic is present
  - When the app starts
  - Then it opens the built-in mic, not a Bluetooth headset

**Notes**: Opening an AirPods mic switches them to call-quality mode, which ruins music playing through them.
Bluetooth mics carry a tooltip saying so. Core Audio's private `CADefaultDeviceAggregate` devices are hidden.

## 002 — Live readings

**Summary**: Waveform, log-frequency spectrum with peak hold, 0–8 kHz spectrogram, RMS/peak meter, noise floor,
dominant frequency, pitch as a note, clip count, and a gain hint.
**Status**: Done (initial commit; host tests for levels, spectrum calibration, pitch, spectrogram; selftest log)

**Use Case**: As Igor, I want to see my mic's level, noise and tone at a glance, so that I can set the gain and
spot hum or hiss.

**Acceptance Criteria**

- Scenario: A quiet mic still shows a waveform
  - Given the mic peaks at -30 dBFS
  - When I look at the waveform
  - Then it is scaled to its own peak and fills the panel, with the scale printed
- Scenario: Gain hint
  - Given my voice peaks under -30 dBFS
  - When I look at the status line
  - Then it says "too quiet — turn gain up"; over -3 dBFS held, "hot — back off gain"
- Scenario: Pitch of a quiet voice
  - Given I hum at 110 Hz at -50 dBFS
  - When I look at the status line
  - Then pitch reads A2

**Notes**: Spectrum is amplitude dBFS (a full-scale sine reads 0 dB). Pitch: FFT autocorrelation, the strongest local
maximum over 60–1000 Hz, gate -60 dBFS. Noise floor: the 10th percentile of the
last 5 s of RMS readings, digital silence ignored (a running minimum latched onto start-up buffers at -110 dB).
