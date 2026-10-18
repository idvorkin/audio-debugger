# Agent instructions: Audio Debugger

macOS app (SwiftUI + AVFoundation + Accelerate) for hearing and seeing what a microphone picks up: live waveform,
spectrum, spectrogram, level meter, noise floor, pitch, and an always-on 20-second replay with pause, scrub, noise
reduction and voice boost. The native port of `py/audio_scope.py` in idvorkin/settings, which went unresponsive
(Qt drawing, FFTs and noise reduction all on one thread under the GIL). Built on magic-monitor-native's pattern.
`Sources/AudioCore/` is the platform-free module (levels, FFT spectrum, pitch, replay ring, transport, denoise, voice
boost, spectrogram pixels); `Sources/AudioDebugger/` is the app. A plain SwiftPM package.

## Build

| Command | What it does |
|---|---|
| `just test` | host tests for AudioCore, about two seconds |
| `just fmt` / `just lint` | swift-format to the house style (`.swift-format`, magic-monitor-native's); lint adds SwiftLint (force unwraps, casts, tries). Run `just fmt` before committing |
| `just selftest [seconds] [mic]` | builds, opens the app hidden and **muted**, captures for `seconds`, scripts replay → pause → seek → toggles → restart, prints the log. `just selftest 6 MacBook` picks the built-in mic |
| `just run` | release build wrapped into `build/Audio Debugger.app`, signed with the Apple Development identity, opened |
| `just live-install` | symlinks `/Applications/Audio Debugger.app` to the build |
| `just logs` | streams the app's log |

- **Builds with the Command Line Tools, not Xcode.** No `@State` (its macro plugin ships only with Xcode): the model
  is an `@Observable` class held by the `App`, and views bind through `Binding(get:set:)`.
- **Run tests with `just test`, not bare `swift test`**: it loads Swift Testing's macro library in-process, which
  the plugin server fails to find on about two builds in three.
- **The mic permission needs the bundle and a stable signature.** `just app` signs with the Apple Development
  identity so macOS keeps the permission across rebuilds; ad-hoc signing asks again every build.
- **Selftest never plays sound** (`Player.muted`): Igor wears headphones while agents work.

## Architecture

| Piece | Where | What |
|---|---|---|
| mics | `Mics` | Core Audio device list (input channels, name, UID, transport), hot-plug listener, the choice: the remembered mic, else USB, else built-in, Bluetooth last (opening an AirPods mic drops them into call-quality mode, music and all) |
| capture | `Capture` | `AVCaptureSession` on the mic by UID, mono float32 at the device rate, into a 20 s `RingBuffer` and a 4096-sample scope window under one lock. **Not AVAudioEngine**: on macOS its input runs through a private aggregate device, and on an input-only USB mic that delivered only zeros |
| readings | `AppModel.tick` | 30 Hz on the main thread: RMS, peak, held peak, noise floor, FFT spectrum, pitch, a spectrogram column. Microseconds with vDSP |
| replay | `Player` | its own `AVAudioEngine` on the default output, an `AVAudioSourceNode` pulling the clip through `Transport` on the render thread; mono into the main mixer feeds both ears. Pause, seek and processing swaps are state changes |
| processing | `AudioCore/Processing` | off the main thread, cached per toggle combination: `denoise` (spectral gating, profile from the quietest 20 % of frames inside the clip) and `voiceBoost` (90 Hz–7.5 kHz band, loud-frame leveling to -16 dBFS, tanh soft limit) |

## Rules

- **Every feature or behaviour change updates the user stories** (`docs/stories/`) in the same commit: Cohn use
  case + Gherkin, a `Status:` line naming the commit and the rung it was verified on.
- **Test ladder**: `just test` → `just selftest` (verified from the log) → `just run` (a real mic and Igor's ears).
  Maths goes in AudioCore with a host test; the app layer stays thin. Say which rung you used.
- **Instrument before theorizing.** Log first (`Log.*`, `privacy: .public`), run, read, then fix from evidence.
  Both capture bugs so far (an engine-restart loop, then all-zero input) were found from the selftest log.
- **Check the mic before blaming the code.** The USB mic (Jieli `USBAudio1.0`, likely a wireless receiver) has gone
  silent (digital zeros) and dropped off the bus by itself. Compare against `just selftest 6 MacBook`.
- **Keyboard first.** Every action has a key (see `Keys` and the stories); the mouse is never required.
- **Edit files with the Read, Edit and Write tools**, not sed or Python in the shell. Never `git add -A`.
- **Audio stays on this Mac.** Nothing is uploaded or saved to disk.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
