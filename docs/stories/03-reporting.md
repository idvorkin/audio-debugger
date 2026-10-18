# When something is wrong

## 006 — Report a bug with the audio that showed it

**Summary**: ⌘I, a sentence, Return: the report keeps the last 20 s the mic heard, the session log, the mic's
readings and the replay's state, and the bug-kit listener files it as a bead.
**Status**: Planned (BugKit wired in; ⌘I to a filed bead not yet verified: run, Igor)
**Why**: "include bug kit" — the USB mic went silent twice with nothing to show for it afterwards.

**Use Case**: As Igor, I want to say "that sounded wrong" the moment it happens, so that whoever fixes it can hear
exactly what I heard.

**Acceptance Criteria**

- Scenario: Report with evidence
  - Given the mic has been open for a minute
  - When I press ⌘I, type "replay is only hiss" and press Return
  - Then `bugs/<time>/` holds `report.json` (note, mic, levels, replay state), the session log and
    `mic-last-20s.wav`, and a line is added to `bugs.jsonl`
- Scenario: Typing is not the transport
  - Given the report sheet is open
  - When I type "r", "space" or "1"
  - Then they go into the note, and no replay or mic switch happens
- Scenario: Filed once
  - Given the bug-kit listener is running
  - When it next polls
  - Then the report becomes one bead in this repo, and later polls never file it again

**Notes**: BugKit's writer, store and format (`exact:` tag); the listener's `mac_dir` is
`~/Library/Application Support/AudioDebugger`. Scripted runs keep their own `selftest/` root.

## 007 — Crashes and logs

**Summary**: A crash leaves a file the next launch announces; session logs are kept (newest 20) for review.
**Status**: Planned (wired in; not yet exercised with a crash)

**Use Case**: As Igor, I want a crash to leave evidence without my doing anything, so that it gets fixed.

**Acceptance Criteria**

- Scenario: A crash is announced once
  - Given the app crashed
  - When it next launches
  - Then the session log has one `crash_report` event and `crashes/` holds the file

## 008 — What's new and About

**Summary**: ⇧⌘N lists the last month's changes by story; Settings shows the version, build and commit.
**Status**: Planned (wired in with the first commits)

**Use Case**: As Igor, I want to see what changed in the build I am running, so that I know what to try.

**Acceptance Criteria**

- Scenario: What's new
  - Given the build bundles whats-new.json
  - When I press ⇧⌘N
  - Then the changes are listed by day, each linked to its story
