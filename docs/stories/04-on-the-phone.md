# On the phone

## 009 — The same scope on an iPhone and iPad

**Summary**: A universal iOS app with the Mac's readings, replay, noise reduction and voice boost: the panels
stacked for a phone held upright, the Mac's layout on an iPad, every action a tap.
**Status**: Done on the simulator (d4f3b8c; 9faf87a and 1b69ef5 recover from interruptions; ios-selftest: live,
replay, pause, seek, toggles, restart, a report with its WAV). On the phone: pending Igor's go for a deploy.
**Why**: "Lets build the iOS version of this too".

**Use Case**: As Igor, I want the audio debugger on my phone, so that I can check a mic (the phone's own, a headset,
a USB receiver) when the Mac is not with me.

**Acceptance Criteria**

- Scenario: Live on the phone
  - Given the app is open on an iPhone with the microphone allowed
  - When I speak
  - Then the waveform, spectrum, spectrogram, meter and readouts move as on the Mac
- Scenario: Replay by tap
  - Given the app has been open for a minute
  - When I tap "▶ 20s"
  - Then the last 20 s play from the speaker (or the headphones), with the replay panel's transport and toggles
- Scenario: Keys on an iPad
  - Given an iPad with a hardware keyboard
  - When I press the Mac's keys (Space, R, N, ←)
  - Then they do what they do on the Mac

**Notes**: Shake, ⌘I or the ⋯ menu reports a bug (BugKit's dialog, with the last 20 s as a WAV); dictation is off,
since it would take over the audio session. The session is `.playAndRecord` in `.measurement` mode: no automatic
gain or voice processing.

## 010 — The phone picks the mic as the Mac does

**Summary**: The audio session's inputs are the mic list: a USB mic, else a wired headset's, else the built-in one;
Bluetooth last, since opening AirPods' mic drops them to call quality.
**Status**: Planned

**Use Case**: As Igor, I want the phone to open the right mic by itself, so that my AirPods keep playing music in
full quality while the phone's mic is measured.

**Acceptance Criteria**

- Scenario: AirPods connected
  - Given AirPods are connected and playing
  - When the app opens
  - Then it opens the built-in mic, and the AirPods keep playing in full quality
- Scenario: A headset plugged in
  - Given the app is open on the built-in mic
  - When I plug in a USB mic or a wired headset
  - Then the list shows it, and the app switches to it
- Scenario: A Bluetooth mic takes its time
  - Given the app is open in a car with its hands-free mic listed
  - When I tap the car's mic
  - Then the app stays responsive while the route comes up, and a second tap meanwhile does not reopen it

**Notes**: Opening a mic runs off the main thread (ad-pdv): the car's mic took 1.8 s to open, which MetricKit
reported as a hang on 12d285f. The fix's commit (mic-open-off-main branch) logs each open's `ms`: the Mac's built-in
mic takes 1.3 s too (selftest). The Bluetooth scenario's phone rung is Igor's next drive.

## 011 — The replay keeps listening in the background

**Summary**: Capture carries on while another app is on screen, so the last 20 s are there on return; the drawing
stops meanwhile.
**Status**: Planned
**Why**: Igor chose background capture over foreground only (2026-10-29).

**Use Case**: As Igor, I want to switch apps and come back to replay what the mic just heard, so that I can check a
call or a recording I made in another app.

**Acceptance Criteria**

- Scenario: Back from another app
  - Given the app captured, then went to the background for 30 s while I spoke
  - When I return and tap "▶ 20s"
  - Then I hear what I said while it was in the background
- Scenario: A call interrupts
  - Given the app is capturing
  - When a phone call takes the mic and then ends
  - Then capture resumes by itself

## 012 — An icon on the Home Screen and in the Dock

**Summary**: Both apps have the same icon: a word's green waveform over a voice's blue spectrum, on the app's dark
panel, drawn by `scripts/make-icon.swift` (`just icon`).
**Status**: Done (12d285f; `just app` bundles the icns; installed on the iPhone, the Home Screen look is Igor's
check)
**Why**: "OK, add an icon too" (Igor, 2026-10-29).

**Use Case**: As Igor, I want to find Audio Debugger by its look, so that I open it without searching.

**Acceptance Criteria**

- Scenario: Home Screen
  - Given the app is installed on the iPhone
  - When I look at the Home Screen
  - Then Audio Debugger shows the waveform-and-spectrum icon, not a blank one
- Scenario: Dock
  - Given the Mac app is open
  - When I look at the Dock
  - Then it shows the same icon
