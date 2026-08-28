# Blurt

Push-to-talk dictation for macOS. Hold a key, talk, release — cleaned-up text lands in
whatever text field has focus. A Wispr Flow-shaped app, built native and fully on-device.

**Status:** working, and in daily use on macOS. Builds, launches, arms the hotkey,
transcribes, cleans up and injects, with a first-run setup flow, a personal dictionary and
an on-device LLM cleanup tier. A Windows port lives in `windows/` — complete, CI-verified,
and never yet run on real hardware.

---

## Coexisting with another dictation app

This app is built to run alongside other dictation tools without colliding with them, which
is not automatic on macOS and is worth understanding before changing anything:

- **Bundle ID `com.lsukev.blurt`** — TCC keys Accessibility and Microphone
  grants to the bundle ID, so granting or revoking a permission here has no effect on any
  other app, and vice versa.
- **Executable `Blurt`** — distinct enough that `pkill -x Blurt` cannot
  match a differently-named binary. The `Makefile` only ever targets `$(EXEC)`.
- **Hotkey is configurable** (Right ⌥ / fn / Right ⌘) precisely because another tool may
  already own the key you'd reach for first. The event tap inspects only its own keycode
  and passes everything else through untouched.

If you run more than one dictation app, give each a different push-to-talk key. Two apps on
the same key both record, and whichever injects text will fight the other.

---

## Quick start

```bash
make install     # builds, bundles, signs, copies to /Applications, launches
```

On a first run Blurt opens its setup flow, which walks you through both permissions, lets
you pick a push-to-talk key, and finishes with a rehearsal so you can confirm the whole
chain works before you rely on it. You can reach it again any time from the menu bar item's
**Run Setup Again…**.

If you'd rather do it by hand, there are two permissions — neither is optional, and neither
can be requested silently:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | The `CGEventTap` that sees the hotkey, and the AX text insert |
| **Microphone** | Prompted on first dictation | Audio capture |

Blurt arms the hotkey the moment Accessibility lands — no restart needed. Then hold
**Right ⌥** and talk.

### Titles and names

Dictating into a **single-line field** — a Name box, a title, a search bar — is treated as a
label rather than a sentence: title case, and no trailing full stop.

That last part needs saying because it is not the same fix as "don't add a period". Blurt
never adds one. Apple's recognizer supplies its own for anything it hears as a complete
sentence, and "Disaster recovery test report" qualifies, so a name field would get a stop
nobody asked for. Nothing about the *words* distinguishes that from a real sentence — the
target does, so the target is what decides.

Detected from the accessibility role (`AXTextField` vs `AXTextArea`) when the key goes down.
Anything unrecognized is treated exactly as before. Abbreviations keep their stop, and
addresses, paths and URLs are left alone entirely.

If it misses in some app, that app is reporting an unexpected role — check the log:

```bash
/usr/bin/log show --predicate 'subsystem == "com.lsukev.blurt"' --last 5m --info | grep "target field"
```

### Choosing what you hold

Any modifier, any key, or any mouse button from the third onwards. Setup offers the four
that are actually good at this — Right ⌥, Right ⌘, fn, Right ⌃ — and "Press any key…"
captures whatever you press next, including F13–F20 and side buttons on a mouse.

Two things the picker will tell you, and they are worth reading. Binding an ordinary key
means Blurt **swallows it system-wide** while running: bind `Q` and you cannot type Q
anywhere. Binding Shift or Control breaks the shortcuts that use them. F13–F20 and
right-hand modifiers cost you nothing, which is why they are the presets.

Left and right mouse buttons are not bindable, by construction rather than by a check.

### Why grants survive rebuilds here

TCC stores a *code-signing requirement* per entry, not just a path. An ad-hoc signature
changes on every build, so the rebuilt binary stops satisfying the stored requirement —
and the symptom is nasty: the Accessibility toggle still **shows as on** while the app is
reported untrusted, and flipping it changes nothing because the stale row is the problem.

The `Makefile` therefore signs with a stable Developer ID (auto-detected via
`security find-identity`, falling back to ad-hoc). Verified: rebuild + reinstall keeps both
grants with no re-prompt.

If a grant ever does get wedged, reset that one row and re-add — never toggle:

```bash
tccutil reset Accessibility com.lsukev.blurt
tccutil reset Microphone   com.lsukev.blurt
```

Always pass the bundle ID. A bare `tccutil reset Accessibility` wipes **every** app on the
machine. Then quit System Settings entirely (⌘Q) before reopening — that pane caches its
list and will otherwise show the row you just deleted.

> **Keep the build out of iCloud.** If `~/Desktop` or `~/Documents` is file-provider synced
> on your machine, the sync engine can materialize/dematerialize files inside an `.app` and
> corrupt its signature. The `Makefile` therefore builds and stages under
> `~/Library/Caches`, which is never synced, and `make install` puts the running copy in
> `/Applications`. Nothing lands in the repo folder.

Other targets: `make app` (bundle only), `make run` (run in place), `make clean`.

### When something isn't working

```bash
/Applications/Blurt.app/Contents/MacOS/Blurt --diagnose
```

Reports the version, whether the on-device model is available and why not, the active
engine, the push-to-talk binding and which event types its tap requests, and how much of
your dictionary reached the engine. Exits non-zero when Blurt cannot dictate as configured.

To check the update feed specifically:

```bash
/Applications/Blurt.app/Contents/MacOS/Blurt --check-updates
```

Fetches the appcast, evaluates it against the installed build, and prints what it found —
headless, no UI. This is what proves a release is actually installable rather than merely
published: it exercises the fetch, the signature check, and the version comparison.

**`--diagnose` cannot report permissions from a terminal, and says so rather than guessing.** TCC
attributes a directly-exec'd process to its responsible parent — your terminal — and answers
on that process's behalf, so both grants read as missing however thoroughly they were
granted. For a report that includes them, use **Copy Diagnostics** in the menu bar item: the
running app is attributed to itself.

(`open -a Blurt --args --diagnose` is not a workaround. Exiting during launch breaks the
LaunchServices handshake and it fails with -600.)

### Cutting a release

```bash
make release VERSION=0.4.0
```

Builds, notarizes, staples, signs the appcast, tags, and publishes to GitHub Releases.
Existing installs pick it up on their next check.

`CFBundleVersion` is bumped by the script, not by hand. Sparkle compares that number — not
the marketing string — so it has to increase monotonically, and hand-editing it is how you
eventually ship a version the updater considers older than what is installed.

### Sending a build to someone else, without releasing

```bash
make notarize
```

Builds release, submits to Apple, staples the ticket onto the `.app`, and writes
`dist/Blurt.zip`. The recipient unzips, drags to `/Applications`, and double-clicks —
nothing to right-click through.

Two details that are easy to get wrong and silently break it:

- **Notarization requires a secure timestamp**, and the ordinary build path deliberately
  passes `--timestamp=none` because timestamping is a network round-trip nobody wants on
  every local build. `make notarize` overrides `TIMESTAMP` for exactly this reason; a
  submission signed without one is rejected before Apple looks at the binary.
- **You staple the `.app`, never the zip.** The zip is only transport, which is why the
  target re-creates it from the stapled bundle rather than reusing the one it submitted.

The credential is set up once and lives in the keychain, never in this repo:

```bash
xcrun notarytool store-credentials blurt-notary   # prompts for everything
```

An App Store Connect API key (`--key`/`--key-id`/`--issuer`) works here too, and avoids
app-specific passwords entirely.

---

## Architecture

```
 hold key ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture  HUDPanel   TranscriptionEngine
                     │                      │
                (AudioChunk) ──ordered──► AppleSpeechEngine
                                            │
                                       (transcript)
                                            ▼
                                      TextFormatter
                                            ▼
                                      TextInjector ─► focused app
```

### Decisions worth knowing

**The HUD must never take focus.** `HUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false`. This is the load-bearing detail of the whole app: if the overlay
took key status, the user's text field would lose focus and there'd be nothing left to
inject into. Everything else is replaceable; this isn't.

**The hotkey needs a `CGEventTap`, not `NSEvent`.** `fn` and left/right modifier
discrimination don't surface through `NSEvent.addGlobalMonitorForEvents` or the Carbon
hotkey API. A session event tap is the only way to see them — which is why Accessibility
permission is a hard requirement rather than a nicety.

**Audio ordering is explicit.** `AudioCapture` yields into an `AsyncStream` drained by a
single task. Spawning a `Task` per buffer would be simpler and would silently corrupt the
transcript, because unstructured tasks have no ordering guarantee.

**Buffers are copied, never borrowed.** `AVAudioEngine` recycles the buffer it hands to a
tap the instant the callback returns. `AudioChunk`'s `@unchecked Sendable` is only sound
because `AudioCapture` always allocates fresh storage before handing off.

**Two swappable seams.** `TranscriptionEngine` and `TextFormatter` are protocols so the
two components most likely to change can change without touching anything else.

### Layout

```
Sources/Blurt/
├── BlurtApp.swift              @main, AppDelegate, MenuBarExtra
├── Core/
│   ├── DictationController.swift   state machine, wires everything
│   ├── HotkeyMonitor.swift         CGEventTap on .flagsChanged
│   ├── AudioCapture.swift          AVAudioEngine tap + format conversion + RMS
│   └── TextInjector.swift          AX insert, pasteboard+⌘V fallback
├── Transcription/
│   ├── TranscriptionEngine.swift   protocol + AudioChunk
│   └── AppleSpeechEngine.swift     SpeechAnalyzer / SpeechTranscriber
├── Formatting/
│   └── TextFormatter.swift         protocol + RuleBasedFormatter
├── Onboarding/
│   ├── OnboardingModel.swift       side effects: prompts, tccutil, relaunch
│   ├── OnboardingView.swift        the lamp rail and the stage
│   ├── OnboardingSteps.swift       welcome / accessibility / microphone / key / done
│   └── TryItStep.swift             the rehearsal, through the real injector
├── UI/
│   ├── DesignSystem.swift          every colour, size, radius and duration
│   ├── Equipment.swift             panels, wells, keys, lamps, meters
│   ├── HUDPanel.swift              non-activating floating panel
│   └── HUDView.swift               waveform + live transcript
└── Support/
    ├── Settings.swift, Permissions.swift, PermissionMonitor.swift, Log.swift

Sources/BlurtDictionary/    correction rules — cross-platform contract, tested
Sources/BlurtSetup/         setup flow decisions — platform-neutral, tested
Sources/BlurtInput/         push-to-talk bindings — naming, suppression, tap scope, tested
```

---

## Speech engine

Default is Apple's **`SpeechAnalyzer` / `SpeechTranscriber`**, new in macOS 26: no
dependency, no bundled model, no cloud path, real streaming with `.volatileResults` so
text appears while you're still talking. The OS downloads and manages model assets, so the
first run for a locale may pause on `AssetInstallationRequest`.

The intended upgrade is **Parakeet v3** via FluidAudio (CoreML on the Neural Engine) —
measurably better English WER, ~110× realtime, ~66 MB resident. Implementing
`TranscriptionEngine` is the entire cost of switching; `DictationController` doesn't
change.

| | Apple SpeechTranscriber | Parakeet v3 (FluidAudio) | Whisper large-v3 (WhisperKit) |
|---|---|---|---|
| Dependency | none | SwiftPM | SwiftPM |
| Model download | OS-managed | ~600 MB | ~1.5 GB |
| English accuracy | good | best | good |
| Languages | many | 25 | 99 |
| Latency | low | ~80 ms | 200–500 ms |

---

## Updates

Blurt checks `https://lsukev.github.io/Blurt/appcast.xml` on launch and daily, and offers
anything newer. **Check for Updates…** is in the app menu and the menu bar item.

Every update is EdDSA-signed, and the public key is in `Info.plist`. That — not access
control — is what makes the public feed safe: the updater carries no credentials, so the
feed and payload were always going to be fetchable by anyone. Someone who compromised the
repo outright still could not ship an update Blurt would install.

**The private key lives in the login keychain and is not recoverable.** Lose it and no
existing install can ever be updated again; they all hold the matching public key and will
reject anything signed with a new one. `generate_keys -x` exports it for backup.

## Not built yet

1. **Command Mode.** Select text, hold a second hotkey, say "make this more formal."
   Needs AX read of `kAXSelectedTextAttribute` plus an LLM round-trip.
2. **A Windows installer**, code signing for it, and model download from inside the app
   rather than by following `docs/PARAKEET-WINDOWS.md` by hand. Windows users meet
   SmartScreen until that's signed.
3. **Windows on real hardware.** Every layer exists and CI exercises it, but nobody has
   yet held the key and spoken into a microphone. Start with `--selftest`.

---

## Verified

Confirmed via `/usr/bin/log show --predicate 'subsystem == "com.lsukev.blurt"'`:

- Builds clean under Swift 6 strict concurrency; 14 tests across two platform-neutral
  targets pass, and both CI workflows are green.
- Signs with a Developer ID, so TCC grants survive rebuild + reinstall.
- Launches as a regular app — Dock icon, app menu, main window — with the menu bar item
  kept for status and the hotkey while you're working elsewhere.
- A first run does **not** throw the system Accessibility dialog before the user has seen
  anything; the setup flow owns that moment. A returning user who lost the grant is still
  asked outright.
- `PermissionMonitor` catches the grant while the app is running, and the event tap arms
  from it without a restart.
- Full state machine: `starting → listening → finishing → idle`, no errors.
- `SpeechAnalyzer` starts, and audio capture converts native 48 kHz → 16 kHz for it.
- HUD renders bottom-center without taking focus.
- Silence produces an empty transcript and injects nothing.

**What no automated test can reach:** speech → transcript → cleanup → injection. CI cannot
speak and cannot hold a key down, which is exactly why the setup flow ends with a rehearsal
that runs the real path into a real focused field — that step is the only place the whole
chain gets exercised on a given machine.

> `log` is shadowed in some shells — use `/usr/bin/log` explicitly or it returns nothing.
