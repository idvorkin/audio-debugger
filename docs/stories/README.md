# Audio Debugger — User Stories

These files are the spec: a feature exists when its story says so. The persona is **Igor, checking how a
microphone sounds before a call or a recording**: a Mac with its built-in mic, a USB mic or receiver, an iPhone
mic, AirPods on his head (often playing music).

| Journey | What it covers |
|---|---|
| [Seeing the mic](01-seeing-the-mic.md) | Choosing a mic, and the live waveform, spectrum, spectrogram, meter and readouts. |
| [Hearing it back](02-hearing-it-back.md) | The always-on replay, its transport, noise reduction and voice boost. |
| [When something is wrong](03-reporting.md) | Reporting a bug with the audio that showed it, crashes, and what changed. |
| [On the phone](04-on-the-phone.md) | The iPhone and iPad app: the same scope by touch, the mic choice, capture in the background. |

## Format

Mike Cohn use case plus Gherkin acceptance criteria. Each story: **Summary**, **Status**, optional **Why**,
**Use Case**, **Acceptance Criteria** (one When and one Then per scenario), optional **Notes**.

**Status** names the commit and the rung it was verified on: `Done (<commit>; host test)`, `(selftest)`, or
`(run: Igor)`. `Planned` until then.

## Keys at a glance

? shows this table in the app (story 016). On an iPad with a keyboard, holding ⌘ lists the same keys.

| Key | Action |
|---|---|
| 1–9 | Switch to that mic |
| Space | Play / pause the replay; with none open, replay the last 20 s |
| R / T / Y | Replay the last 5 / 10 / 20 s (F also replays 5 s) |
| A | Replay from the start |
| ← / → (⇧ for 5 s) | Jump back / forward 1 s |
| N / B | Noise reduction / voice boost on and off |
| C | Reset held peaks, clip count and the noise readout |
| S | Save the last 20 s as a WAV with its measurements |
| H | Open the noise explainer (what floor, speech and separation mean) |
| ? | Show every key |
| Esc or ⌘. | Close the key sheet, else the replay |
| ⌘I | Report a bug |
| ⇧⌘N | What's new |
