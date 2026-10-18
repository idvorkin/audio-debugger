app := "build/Audio Debugger.app"
installed := "/Applications/" + file_name(app)
# With the Command Line Tools, finding Swift Testing's macros through the plugin server fails on about two builds
# in three ("plugin for module 'TestingMacros' not found"). Loading the library in-process never has.
testing_macros := "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

default:
    @just --list

# Host tests for AudioCore. The first rung of the test ladder.
test:
    #!/usr/bin/env bash
    # pipefail: a failing suite must fail the recipe instead of hiding behind tail's exit 0.
    set -uo pipefail
    swift test -Xswiftc -load-plugin-library -Xswiftc "{{testing_macros}}" 2>&1 | grep -E "error:|✘|Test run" | tail -20

swift_files := "Sources Tests Package.swift"

# Format every Swift file in place to the house style (.swift-format, as magic-monitor-native).
fmt:
    swift format format -i -r {{swift_files}}

# Style (swift-format) and crashes waiting to happen (SwiftLint: force unwrap, cast and try in the app code).
lint:
    swift format lint --strict -r {{swift_files}}
    swiftlint lint --strict --quiet

# Build a release binary and wrap it into a signed app bundle (the microphone permission needs the bundle).
app:
    #!/usr/bin/env bash
    set -uo pipefail
    out=$(swift build -c release 2>&1)
    echo "$out" | grep -E "error:|Build complete"
    echo "$out" | grep -q "Build complete" || exit 1
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources"
    cp "$(swift build -c release --show-bin-path)/AudioDebugger" "{{app}}/Contents/MacOS/"
    cp Support/Info.plist "{{app}}/Contents/"
    git describe --always --dirty > "{{app}}/Contents/Resources/commit.txt" 2>/dev/null || echo none > "{{app}}/Contents/Resources/commit.txt"
    # BugKit's About reads the build's commit and the repository from Info.plist.
    /usr/libexec/PlistBuddy -c "Add :BugKitCommit string $(git describe --always --dirty --abbrev=40 --exclude='*' 2>/dev/null || echo unknown)" \
      -c "Add :BugKitRepositoryURL string https://github.com/idvorkin/audio-debugger" "{{app}}/Contents/Info.plist"
    # What's new: the last month of commits by story (BugKit's script; never fails the build).
    sh .build/checkouts/bug-kit/scripts/whats-new.sh "{{app}}/Contents/Resources/whats-new.json" --repo . \
      --base-url "https://github.com/idvorkin/audio-debugger/blob/main/docs/stories/" >/dev/null 2>&1 || true
    # Signed with the Mac's Apple Development identity so the designated requirement is the same every build and
    # macOS keeps the microphone permission across rebuilds. Ad-hoc only when there is no identity.
    id="${AD_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
    [ -n "$id" ] || echo "warning: no Apple Development identity: ad-hoc signing, so macOS asks for the mic again" >&2
    codesign --force --sign "${id:--}" "{{app}}"

_quit-app:
    #!/usr/bin/env bash
    if pgrep -x AudioDebugger >/dev/null; then pkill -x AudioDebugger; sleep 1; fi

# Build the app and open it: the top rung (a real mic and Igor's ears).
run: app _quit-app
    open "{{app}}"

# Symlink /Applications to this checkout's build, so each `just app` is what Spotlight and the Dock open.
live-install: app
    rm -rf "{{installed}}"
    ln -s "{{justfile_directory()}}/{{app}}" "{{installed}}"

# Open the app in the background (on `mic` if given, e.g. `just selftest 6 MacBook`), muted, run the scripted flow
# (levels, mic list, replay, noise reduction, voice boost, pause, seek, restart) and print its log. Plays nothing.
selftest seconds="6" mic="": app _quit-app
    #!/usr/bin/env bash
    set -uo pipefail
    start=$(date "+%Y-%m-%d %H:%M:%S")
    mic=()
    [ -n "{{mic}}" ] && mic=(--mic "{{mic}}")
    open -g -j -W "{{app}}" --args --selftest {{seconds}} "${mic[@]}"
    log show --start "$start" --predicate 'subsystem == "com.idvorkin.audiodebugger"' --info --style compact \
      | grep -vE "^Timestamp|^Filtering" | cut -c 25-

# README screenshots into docs/: the app opens in the background (no focus taken) on `mic`, muted, for ~15 s;
# each shot is its window, captured by `screencapture -l` (the terminal's Screen Recording permission).
screenshots mic="MacBook": app _quit-app
    #!/usr/bin/env bash
    set -uo pipefail
    dir="$HOME/tmp/agent/audio-debugger/screens"
    rm -rf "$dir"; mkdir -p "$dir"
    open -g "{{app}}" --args --screenshots "$dir" --mic "{{mic}}"
    for shot in live replay; do
      for _ in $(seq 60); do [ -f "$dir/$shot.wid" ] && break; sleep 0.5; done
      [ -f "$dir/$shot.wid" ] || { echo "no $shot shot"; exit 1; }
      screencapture -o -x -l "$(cat "$dir/$shot.wid")" "docs/$shot.png" && echo "docs/$shot.png"
    done

# The session log (JSON Lines) of the newest launch: everything the app saw and did.
session-log:
    @ls -t "$HOME/Library/Application Support/AudioDebugger/logs/"*.jsonl | head -1 | xargs cat | jq -c .

# Stream the app's log (mics, levels, replay, processing).
logs:
    log stream --predicate 'subsystem == "com.idvorkin.audiodebugger"' --level info
