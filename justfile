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

swift_files := "Sources Tests iOS Package.swift"

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
    #!/usr/bin/env bash
    set -uo pipefail
    # Quoted: the path has a space ("Application Support"), which split an unquoted `xargs cat` in two.
    f="$(\ls -t "$HOME/Library/Application Support/AudioDebugger/logs/"*.jsonl 2>/dev/null | head -1)"
    [ -n "$f" ] || { echo "no session logs yet (just run first)"; exit 1; }
    jq -c . "$f"

# Stream the app's log (mics, levels, replay, processing).
logs:
    log stream --predicate 'subsystem == "com.idvorkin.audiodebugger"' --level info

# ---- iPhone and iPad (Xcode). Everything below is the build lane: run it under ~/tmp/agent/locks/build.lock. ----

ios_app := "build/ios/Build/Products/Debug-iphoneos/Audio Debugger.app"
ios_sim_app := "build/ios/Build/Products/Debug-iphonesimulator/Audio Debugger.app"
iphone_udid := "00008150-000A31D10CF2401C"  # Igor iPhone 17 Pro

# Generate the iOS Xcode project from iOS/project.yml (xcodegen; not checked in), resolving BugKit at the revision
# the Mac's committed Package.resolved pins.
ios-project:
    cd iOS && xcodegen generate --quiet
    mkdir -p iOS/AudioDebuggerPhone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
    cp Package.resolved iOS/AudioDebuggerPhone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# Build the iOS app for the simulator: AudioCore, the shared app layer and iOS's own files (iOS/).
ios-build: ios-project
    #!/usr/bin/env bash
    set -uo pipefail
    xcodebuild -project iOS/AudioDebuggerPhone.xcodeproj -scheme AudioDebuggerPhone \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios \
      BUGKIT_COMMIT="$(git describe --always --dirty --abbrev=40 --exclude='*')" build 2>&1 | just _xcb
    grep -q "BUILD SUCCEEDED" build/ios/xcodebuild.log

# xcodebuild's output for a person: errors only. The whole raw output is kept in build/ios/xcodebuild.log, and pass
# or fail is read from there, never from the filtered output.
_xcb:
    #!/usr/bin/env bash
    mkdir -p build/ios
    cat > build/ios/xcodebuild.log
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" build/ios/xcodebuild.log | sort -u | head -40
    echo "full log: build/ios/xcodebuild.log"

# The selftest's flow on a headless iPhone simulator (`audio-debugger-iphone`, made on first use), muted, then the
# app's log. The simulator's mic is the Mac's default input. Shuts the simulator down however it ends.
ios-selftest seconds="6": ios-build
    #!/usr/bin/env bash
    set -uo pipefail
    sim=audio-debugger-iphone bundle=com.idvorkin.audiodebugger
    fail() { echo "ios-selftest FAILED: $*" >&2; exit 1; }
    if ! xcrun simctl list devices available | grep -q "$sim ("; then
      type=$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone-17[^)]*' | head -1)
      xcrun simctl create "$sim" "$type" >/dev/null || fail "could not create $sim"
    fi
    # One simulator on this Mac at a time.
    others=$(xcrun simctl list devices booted | grep "(Booted)" | grep -v "$sim (" || true)
    [ -z "$others" ] || fail "another simulator is booted: $others"
    trap 'xcrun simctl shutdown "$sim" 2>/dev/null' EXIT
    xcrun simctl bootstatus "$sim" -b >/dev/null || fail "could not boot $sim"
    xcrun simctl install "$sim" "{{ios_sim_app}}" || fail "install"
    xcrun simctl privacy "$sim" grant microphone "$bundle" || fail "could not grant the microphone"
    start=$(date "+%Y-%m-%d %H:%M:%S")
    xcrun simctl launch --terminate-running-process "$sim" "$bundle" --selftest {{seconds}} >/dev/null || fail "launch"
    # The script quits the app at its end, about 10 s after the capture: wait for it to be gone. Into a variable
    # first: `| grep -q` under pipefail fails on a match.
    running=yes
    for _ in $(seq 1 $(( {{seconds}} + 60 ))); do
      sleep 1
      jobs=$(xcrun simctl spawn "$sim" launchctl list)
      grep -q "UIKitApplication:$bundle" <<<"$jobs" || { running=no; break; }
    done
    log=$(xcrun simctl spawn "$sim" log show --start "$start" --predicate 'subsystem == "com.idvorkin.audiodebugger"' --info --style compact \
      | grep -vE "^Timestamp|^Filtering" | cut -c 25-)
    echo "$log"
    [ $running = no ] || { xcrun simctl terminate "$sim" "$bundle" 2>/dev/null; fail "timed out: the script was still running"; }
    grep -q "selftest done" <<<"$log" || fail "the app ended before the script finished"
    grep -q "replay open true" <<<"$log" || fail "replay did not open"

# Build, install and open the app on Igor's iPhone (or another UDID from `xcrun devicectl list devices`), then record
# the deploy for the mac-driver. Takes the signing lock itself: wrap it in build.lock only.
iphone device=iphone_udid:
    @mkdir -p "$HOME/tmp/agent/locks"
    @lockf -k -t 900 "$HOME/tmp/agent/locks/xcode-signing.lock" just _iphone-locked {{device}}; rc=$?; \
      [ $rc = 75 ] && echo "error: no signing build: the signing lock was not free within 15 minutes" >&2; exit $rc

# `just iphone` under the signing lock; not run by itself.
_iphone-locked device:
    #!/usr/bin/env bash
    set -uo pipefail
    just ios-project || exit 1
    # bug-kit's signing guard: waits for an unlocked screen (a provisioning build on a locked Mac drops Igor's Apple
    # ID); on "No Accounts" it returns 78: stop, never retry.
    guard=.build/checkouts/bug-kit/scripts/signing-guard.sh
    [ -f "$guard" ] || swift package resolve >/dev/null || { echo "error: no bug-kit checkout for the signing guard" >&2; exit 1; }
    bash "$guard" xcodebuild -project iOS/AudioDebuggerPhone.xcodeproj -scheme AudioDebuggerPhone \
      -destination "platform=iOS,id={{device}}" -derivedDataPath build/ios \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      BUGKIT_COMMIT="$(git describe --always --dirty --abbrev=40 --exclude='*')" build 2>&1 | just _xcb
    rc=${PIPESTATUS[0]}
    if [ "$rc" = 78 ]; then
      echo "error: No Accounts: Xcode lost the Apple ID. Stop, don't retry; Igor signs in at Xcode › Settings › Accounts" >&2
      exit 78
    fi
    [ "$rc" = 0 ] && grep -q "BUILD SUCCEEDED" build/ios/xcodebuild.log || { echo "error: the iOS build failed" >&2; exit 1; }
    # A failed install must not go on to open the copy already on the phone.
    xcrun devicectl device install app --device {{device}} "{{ios_app}}" \
      || { echo "error: built, but the install failed (is the phone connected and unlocked?)" >&2; exit 1; }
    ~/gits/mac-driver/bin/record-deploy audio-debugger phone "$(git rev-parse HEAD)" || true
    launch=$(xcrun devicectl device process launch --device {{device}} com.idvorkin.audiodebugger 2>&1) && { echo "$launch"; exit 0; }
    echo "$launch"
    grep -qE "10002|[Ll]ocked" <<<"$launch" && { echo "installed; the phone is locked: unlock it and open Audio Debugger"; exit 0; }
    echo "error: installed, but the launch failed" >&2
    exit 1
