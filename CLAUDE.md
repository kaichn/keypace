# KeyPace: notes for Claude

A native macOS menu bar app (SwiftUI, macOS 26+) that measures typing speed passively. It is
public at github.com/kaichn/keypace. See README.md for features, definitions and layout.

## Git and GitHub

- **Commit messages:** end them with `Co-Authored-By: Claude …` only. Never add a
  `Claude-Session:` link, in commits, tags or PR bodies.
- **Author email:** commit as `89603327+kaichn@users.noreply.github.com`; it is already set in
  this repo's git config. GitHub rejects pushes that expose the private email.
- **Public history:** don't rewrite history that's already on GitHub unless asked.
- **Remote:** `git@github.com:kaichn/keypace.git`, over SSH.
- **Creating public repos:** the permission classifier blocks this. Ask the user to run it.
- **`notes/`:** local only, excluded through `.git/info/exclude`. Never commit it.

## Releases

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` with `sed`.
   PlistBuddy reformats the whole file.
2. Run `./build.sh release`. It tests, builds a universal app, and writes
   `dist/KeyPace-<version>.zip` plus a `.sha256`.
3. Commit, then `git tag -a v<version>`, then `git push --follow-tags`.
4. Run `gh release create v<version> dist/KeyPace-<version>.zip dist/KeyPace-<version>.zip.sha256`.
   - **Release notes:** list only what changed (Fixed / Added / Changed). No install or
     Gatekeeper steps; the README covers those.
   - **Version numbers:** the user picks them. Don't assume the next one.

## Building

- **Day to day:** `./build.sh install` runs the tests, builds, replaces `/Applications/KeyPace.app`
  and relaunches it.
- **Signing:** builds are signed with the local "KeyPace Local Signing" certificate. Keep it, so
  Input Monitoring and Keychain access survive rebuilds.
- **SDK stamp:** keep the `vtool` stamp in `build.sh`. Without it, macOS runs the app without
  Liquid Glass.
- **Speed maths:** every change to it needs a test in `Tests/KeyPaceTests/SpeedMathTests.swift`.

## Testing on the user's Mac

- **Opening windows or typing on screen:** say so first. This covers demo copies, Spotlight
  tests, and anything else that appears on the user's screen.
- **Demo or screenshot runs:** use a separate data folder:
  `KEYPACE_DATA_DIR=<scratch dir>`.
  - **Defaults are shared:** they live in the real domain (`com.charl.keypace`). Never pass
    `-paused YES`, because AppModel writes it back and pauses the real app.
  - **Locale:** pass `-AppleLocale en_US -AppleLanguages "(en)"` so screenshots use English
    number and date formats.
- **Test sessions in the real database:** if a test reaches
  `~/Library/Application Support/KeyPace/keypace.sqlite`, back it up
  (`.bak-<date>-<purpose>`), delete exactly those rows, and tell the user.
- **Diagnostics:** `/usr/bin/log stream --predicate 'subsystem == "com.charl.keypace"' --level info`.
  Use the full path, because zsh has a `log` builtin.

## Product decisions

- **Default unit:** WPM, with 5 characters per word, the same as Monkeytype.
- **Text is never stored:** key events are classified and discarded. Only counts and timing are
  kept.
- **Keys count for the app that receives them** (the event's target process), not the frontmost
  app. Spotlight on this macOS shows up as *Siri AI* (`com.apple.campo`).
- **Gaming pause:** Game Mode's on/off state is only on gamepolicyd's privileged XPC
  interface, so `GameDetector` applies Game Mode's own rules instead: games categories plus
  Apple's database in `/System/Library/AssetsV2/com_apple_MobileAsset_GamePolicy_DB1`
  (process names there are cut to 15 characters). Ignore `com.apple.GameOverlayUI`
  activations: that is the "Game Mode on" banner.
- **Pause button:** keep it a plain glass `Button`. A SwiftUI `Menu` in the popover draws as a
  pop-up control; the durations open as an `NSMenu` (`PauseMenu`).
- **Monkeytype:** the API is read-only, so results can be imported but never uploaded.
- **Copyright and license:** © 2026 Carl Chen, MIT License, shown in the About panel and in LICENSE.
