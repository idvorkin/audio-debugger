# The explainer

The noise explainer (H, `docs/noise.html`) teaches what the app's numbers mean. This journey adds live pictures to
it: the same waveform, spectrum, spectrogram and noise readout the app draws, computed by the app's own analysis
code running in the browser, so a picture in the explainer and a reading in the app can never disagree.

## 014 — A live demo in the explainer, loaded on request

**Summary**: A "Load live demo" button in the explainer loads the app's analysis code into the page and shows
moving pictures of sound: waveform, spectrum, spectrogram, and the noise floor, speech level and separation with
its GOOD / OK / POOR / "no speech heard" band.
**Status**: Planned
**Why**: Igor, 2026-11-24: "Visualizing noise is going to need some pictures … maybe we share the code with the
audio debugger, with a button to load the Wasm."

**Use Case**: As Igor (or anyone I send the page to), I want to see what a noise floor and a separation look like
while I read about them, so that the numbers mean something before I open the app.

**Acceptance Criteria**

- Scenario: The page stays light until asked
  - Given I open the explainer
  - When the page loads
  - Then it shows the static text and diagrams as today, with a "Load live demo" button, and downloads nothing more
- Scenario: Scenes without a microphone
  - Given I press "Load live demo"
  - When it has loaded (a second or less on a laptop)
  - Then I can pick a scene (quiet room, fan, gym, café, hum) and a voice level, and see the waveform, spectrum and
    spectrogram move, with the floor, speech and separation and its band below them; no permission is asked
- Scenario: The same answer as the app
  - Given a scene's audio saved as a WAV
  - When the app's saved-sample measurement and the page's readout both measure it
  - Then floor, speech and separation agree to 0.1 dB, and the band is the same
- Scenario: My own microphone
  - Given the demo is loaded
  - When I press "Use my mic" and allow it
  - Then the pictures and readout follow my mic live, and talking moves the band from "no speech heard" toward
    GOOD; nothing is recorded or uploaded
- Scenario: The mic is refused or unavailable
  - Given I deny the permission, or the page is opened from a file where the browser does not offer the mic
  - When I press "Use my mic"
  - Then a line says why, and the scenes keep working
- Scenario: Offline, from the app
  - Given I press H in the Mac app with no network
  - When the page opens and I press "Load live demo"
  - Then the demo loads from the app's own copy
- Scenario: Every browser Igor uses
  - Given Safari, Chrome, and the iPhone's Safari
  - When I load the demo at laptop and phone widths
  - Then it runs with no console errors and no sideways scroll, in light and dark

**Notes**: The bands come from the app's own code, so the page's table and the demo cannot drift apart. The demo
measures in the browser: audio never leaves the device.
