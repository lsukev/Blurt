# Working on this repo

Read this before changing anything. It is written for a coding agent picking the project up
cold, and it is mostly a list of things that look wrong but aren't, plus things that look
fine and will bite you.

---

## What this is

Push-to-talk dictation. Hold a key, talk, release, and cleaned-up text is typed into
whatever had focus. Two independent implementations:

| | macOS | Windows |
|---|---|---|
| Language | Swift 6 | C# / .NET 10 |
| UI | SwiftUI | Avalonia |
| Speech | Apple `SpeechAnalyzer`, or Parakeet via FluidAudio | Parakeet via sherpa-onnx |
| Location | repo root | `windows/` |

**The macOS app works and is in daily use.**

**The Windows app is complete but has never run on real hardware.** Every layer exists;
CI builds it, runs 63 tests, publishes a single-file executable, launches it on Windows and
confirms the platform layer loads and constructs. What has never happened is a person
holding the key and speaking into a microphone. Describe it that way — not as "working",
not as "unfinished".

---

## The one rule that matters

**`shared/dictionary-test-vectors.json` is the specification for correction behaviour.**

Both implementations run it in CI. If you change how corrections work, change the vectors
first, watch both sides go red, then make them green. Changing one implementation to "fix"
a failing vector without changing the other is how the two silently diverge — and only one
of them can be exercised by hand.

```bash
swift test --filter VectorTests                    # macOS side
cd windows && dotnet test Blurt.CrossPlatform.slnf # Windows side, runs anywhere
```

A third, `BlurtInput`, holds what you hold to dictate: naming, the suppression policy,
storage migration and — importantly — which event types the tap is allowed to ask for.
`swift test --filter BlurtInputTests`. Three rules there are load-bearing:

- **The tap's event mask is derived from the binding, never fixed.** A session tap that asks
  for `keyDown` observes every character typed anywhere on the machine. Blurt has no
  business holding that while it waits on a modifier or a mouse button, so it doesn't ask.
  Rebinding tears the tap down and builds a new one. Don't "simplify" this to one mask.
- **Left and right click are unrepresentable, not rejected.** `mouseButton(_:)` returns nil
  below button 2 and the tap only ever requests `otherMouse` events, so binding left-click
  is impossible by construction. Keep it that way rather than adding a check.
- **A swallowed key must be swallowed on both edges.** Consume the down and let the up
  escape and the target app believes the key is held forever — the same failure the Windows
  hook section describes. `transition(to:)` returns the same answer for both edges on
  purpose.

There is a second platform-neutral target with the same shape: `BlurtSetup` holds the
first-run flow's *decisions* — step order, which lamps are lit, when the wedged-TCC reset is
worth offering — precisely so they can be tested without macOS 26, a microphone or a TCC
database. `swift test --filter SetupFlowTests`. The side effects live in `OnboardingModel`
in the app target and are not testable; keep the seam where it is.

The Swift copy at `Tests/BlurtDictionaryTests/dictionary-test-vectors.json` is a copy, and
CI fails if it drifts from `shared/`. After editing the shared file:

```bash
cp shared/dictionary-test-vectors.json Tests/BlurtDictionaryTests/
```

---

## Things that look like bugs and are not

**`dotnet build Blurt.sln` fails on macOS** with `NETSDK1073`. Expected —
`Blurt.Platform.Windows` targets `net10.0-windows`. Use `Blurt.CrossPlatform.slnf`, which
omits it; everything else, including the whole UI suite, builds and tests on macOS in about
half a second.

**`swift build` fails with "input file was modified during the build."** This happens when
the checkout sits in a file-provider-synced folder (iCloud Desktop & Documents, Dropbox) and
the sync engine touches files mid-compile. It is not universal — check before repeating it
as fact about a given machine. **Always build with `make`** regardless: it uses
`--scratch-path` under `~/Library/Caches`, which is never synced, so the race cannot happen
and no `.build/` lands next to the source. If you see this error, wait a few seconds and
retry.

**Compare mode doesn't type anything.** By design — `Settings.compareMode` runs every engine
on one recording and shows them side by side. If both injected, two transcripts would fight
over one text field. This is the single most confusing behaviour in the app.

**The timing column isn't comparing like with like.** Apple and Parakeet are timed on local
compute with the clock started *after* model load. Wispr Flow's number is its own
`e2eLatency`, which includes a network round trip and its cleanup pass. Don't present them
as one ranking.

**`MainActor.assumeIsolated` will crash the process.** It does not check the claim, it
asserts it. Use `await MainActor.run` from any non-main-actor context. This took the app
down once already.

**Mutating `@State` inside a `Canvas` draw closure floods the log and corrupts state.** The
VU meter keeps its needle physics in a plain reference type the view merely holds, which is
invisible to SwiftUI's state graph. Don't "clean that up" into `@State`.

---

## Design system

`Sources/Blurt/UI/DesignSystem.swift` defines every colour, size, radius, duration
and material token. **Views must not contain literal values.** If a component needs a number
that isn't a token, add the token rather than inlining it.

The direction is 1980s field recorders — Sony TC-D5, Marantz PMD, Nakamichi, Braun. Silver
face in light appearance, black face in dark. Two rules that are not negotiable:

- **Red means recording.** Nothing else in the app is red.
- **Amber and green are instrumentation only** — level meters, never UI chrome.

A consequence worth stating, because it catches people: a "granted"/"done" indicator cannot
be green, which is the colour every other app reaches for. Use `DS.Color.statusLamp` — warm
white, which is what function lamps on the actual hardware were.

Explicitly ruled out: neon, vaporwave, synthwave, purple/pink gradients, glowing text, chrome
lettering, grid horizons. There are **no gradients anywhere**; depth comes from flat panels,
hairline bevels and procedurally-drawn brushed grain.

---

## macOS specifics

**Code signing is load-bearing, not cosmetic.** TCC stores a code-signing *requirement* per
entry, not just a path. An ad-hoc signature changes every build, so the rebuilt binary stops
satisfying the stored requirement — and the symptom lies: the Accessibility toggle still
shows as **on** while the app is untrusted. The `Makefile` auto-detects a Developer ID via
`security find-identity`. Don't replace that with `--sign -`.

If a grant does get wedged, reset that one row — never toggle, and never omit the bundle ID:

```bash
tccutil reset Accessibility com.lsukev.blurt
```

A bare `tccutil reset Accessibility` wipes every app on the machine. Then quit System
Settings entirely (⌘Q) before reopening; the Privacy pane caches its list.

**`log` may be shadowed in the user's shell.** Use `/usr/bin/log` explicitly.

**TCC answers for the parent process, not for a shell-exec'd child.** Run
`Blurt --diagnose` from a terminal and `AXIsProcessTrusted()` returns false on a machine
where Accessibility is granted — TCC attributes the process to the terminal that spawned it.
Measured both ways: the same binary launched by LaunchServices arms its event tap, while the
shell-exec'd copy reports the grant missing. `Diagnostics` therefore refuses to report
permissions unless `getppid() == 1`, and the menu's **Copy Diagnostics** is the path that can
see them. Don't "fix" this with `open -a Blurt --args --diagnose`: exiting during launch
breaks the LaunchServices handshake and fails with -600.

**Don't run the `.app` from the repo folder.** It's iCloud-synced and the sync engine can
corrupt the signature. `make install` puts the running copy in `/Applications`.

---

## Windows specifics

The specifics below were expensive to establish and several were found the hard way. Treat
them as load-bearing. Full detail in `windows/README.md` and `docs/PARAKEET-WINDOWS.md`.

**Three pinned versions that break silently at "latest":**

| Package | Pin | Why |
|---|---|---|
| `NAudio` | 2.3.0 | 3.x targets .NET 9+ and will not restore |
| `Avalonia.Headless.XUnit` | 11.3.20 | 12.x requires xUnit **v3**, a different package line |
| `org.k2fsa.sherpa.onnx` | 1.13.5 | Bundles ONNX Runtime — never also reference `Microsoft.ML.OnnxRuntime` |

**Right Alt is AltGr** on German, Polish, UK, Nordic and most Latin-American layouts. Binding
push-to-talk there — and especially suppressing it — breaks typing `@`, `€`, `\`, `|` for
those users. Default is **Right Ctrl**, and the hook **observes without swallowing**: if the
key-down is swallowed and the key-up escapes, the target app believes Ctrl is held forever.

**UI Automation cannot inject text.** `TextPattern` is documented read-only and
`ValuePattern` replaces a whole field rather than inserting at the caret. `SendInput` is the
primary path, not a fallback.

**`Blurt.App` loads the platform layer by reflection, not by reference.** A direct
reference would force the UI onto `net10.0-windows` and you would lose the ability to run it
on your own machine. Two consequences that have already bitten once: the assembly is
invisible to `PublishSingleFile`, so it is published as a loose file beside the exe *and*
resolved by an explicit `AssemblyLoadContext` handler; and the published self-test checks
this, because when it breaks the app starts perfectly and then does nothing at all when the
key is pressed.

**Keep `Blurt.Platform.Windows` logic-free.** Anything living there is code CI cannot
exercise. Retries, debouncing and device-change handling belong in the platform-neutral
projects behind an interface — those target plain `net10.0`, so `CA1416` turns any accidental
Win32 call into a build error.

**CI is the only place the Windows code is compiled.** Warnings are errors and the analyzers
are strict on purpose. `--no-incremental` is mandatory: Roslyn does not re-emit analyzer
warnings on a cached build, so without it the gate proves nothing.

---

## Regex, if you touch the dictionary

The two engines are not identical. Measured across 30 cases, **9 diverged**. Two affect this
code and are handled — don't remove either:

- `RegexOptions.CultureInvariant` on the C# side, or Turkish `İ` matches `i`.
- **NFC normalization on both sides.** macOS returns decomposed strings, so without it an
  accented trigger silently never fires.

Two more are unfixable and simply avoided: ICU folds `ß` to `ss` and .NET doesn't; .NET's `.`
splits surrogate pairs. Stay inside the safe subset — `\b`, `\d`, `\w`, `\s`, character
classes, greedy/lazy quantifiers, alternation, `(?<name>…)`, fixed-length lookbehind,
lookahead, `\p{L}`, and `$1`–`$9` in replacements. Nothing else.

---

## What isn't built

1. **Command Mode** — select text, hold a second key, "make this more formal."
2. **Code signing on Windows.** Windows users meet SmartScreen. macOS is done: `make
   notarize` signs with a Developer ID, submits, and staples, so a handed-over build opens
   normally. Two traps live in that target and are commented there — notarization needs a
   secure timestamp, which the ordinary build path deliberately omits, and you staple the
   `.app` rather than the zip.
4. **An installer** for Windows, and model download from inside the app rather than by
   following `docs/PARAKEET-WINDOWS.md` by hand.

## What no amount of CI can verify

On Windows, nobody has yet held the key and spoken. Specifically unverified:

- Text injection landing in a foreground app — runners have an interactive desktop but
  cannot take the foreground.
- A real microphone: format negotiation, the OS privacy block, unplugging mid-capture.
- The keyboard hook firing on a physical keypress.
- Parakeet transcribing real speech, and whether ~2 GB resident is tolerable.

Everything those feed into is behind an interface and tested with fakes. The bindings
themselves are not. **First real-hardware run should start with `--selftest`, then a single
short dictation into Notepad.**
