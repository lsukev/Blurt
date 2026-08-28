# In-app updates

**Status:** implemented
**Date:** 2026-08-28

Blurt checks for new versions, tells the user, and installs one on request. Built on
Sparkle 2, fed by a GitHub Pages appcast, releasing from a local `make release`.

---

## Why Sparkle rather than something smaller

A custom updater that polls the GitHub releases API and shows a panel is about 150 lines
and needs no framework, no keys and no build changes. It also cannot install anything.

Replacing a running `.app` and relaunching it is the hard part of this problem, and it is
the part where a hand-rolled version corrupts someone's installation. Satisfying "allow you
to install it" means writing exactly the component nobody should write themselves. So:
Sparkle, and the cost lands in the build rather than in the app.

Two prerequisites are already met. Blurt is **not sandboxed**, which is what makes Sparkle
straightforward instead of painful, and it is **notarized**, which the installed update
needs in order to launch cleanly.

---

## Hosting

The appcast is served by **GitHub Pages from `/docs` on `main`**:

```
https://lsukev.github.io/Blurt/appcast.xml
```

Not `raw.githubusercontent.com`. That is the obvious shortcut and it is wrong here: it
carries a CDN cache of several minutes, GitHub does not support it as a production
endpoint, and the symptom of using it is that a freshly published update is invisible for a
while — indistinguishable from a bug in your own code. `SUFeedURL` requires HTTPS, which
Pages provides.

**Pages must be enabled on the repo** — Settings ▸ Pages ▸ source `main` / `/docs`. Until
that is switched on the feed URL 404s, and Sparkle reports it as "no update available"
rather than as a broken feed, which is a confusing first failure.

Update payloads are ordinary GitHub release assets. Verified reachable without
credentials:

```
https://github.com/lsukev/Blurt/releases/download/v0.1.0/Blurt.zip  →  200
```

---

## Components

```
Sources/Blurt/Updates/UpdateController.swift   @Observable wrapper over Sparkle
docs/appcast.xml                                the feed, published via Pages
Tools/release.sh                                the release pipeline
```

`UpdateController` stays thin. It owns an `SPUStandardUpdaterController` and publishes
`isChecking`, `lastCheckedAt` and `checkForUpdates()` so menus and Settings can bind to it.
Sparkle owns the update UI itself — see "Accepted mismatch" below.

It is instantiated once by `AppDelegate`, alongside `controller` and `hud`, and handed to
the views that need it. Not a singleton: `PermissionMonitor` is shared because the event tap
and the UI genuinely observe the same system state, whereas nothing needs a second updater.

`Info.plist` gains four keys:

| Key | Value | Why |
|---|---|---|
| `SUFeedURL` | the Pages URL above | where to look |
| `SUPublicEDKey` | the EdDSA public key | what to trust |
| `SUEnableAutomaticChecks` | `YES` | set explicitly — see below |
| `SUScheduledCheckInterval` | `86400` | daily |

---

## Build

Three changes, one of which is where this goes wrong.

**Link and embed.** SwiftPM links frameworks but does not embed them — that is Xcode's job,
and this project hand-assembles its bundle in the `Makefile`. So the `app` target copies
`Sparkle.framework` into `Contents/Frameworks/`, and the executable is linked with

```
-Xlinker -rpath -Xlinker @executable_path/../Frameworks
```

That flag goes on the `swift build` line in the `Makefile`, **not** in `Package.swift` as
`linkerSettings`. In the manifest it would also apply during `swift test` in CI, which does
not link Sparkle and does not need it, and `.unsafeFlags` in a manifest is a wart that
spreads to anything depending on the package.

Without the rpath the app builds, signs, notarizes, and then dies at launch with a dyld
error — a failure that appears only in the finished artifact.

**Signing goes inside-out.** The current `codesign` call signs one binary. Sparkle's
framework contains nested executables — `Autoupdate`, `Updater.app`, and XPC services —
and each needs signing with hardened runtime and a secure timestamp *before* the framework,
which must be signed before the app. Deepest first, app last.

Do not use `--deep`. It is deprecated and does not apply entitlements correctly. Signing the
app first produces a notarization rejection whose message points at the framework rather
than at the ordering, which is a long way to go to learn you did it backwards.

**Version becomes an input.** Sparkle decides *is this newer* from `CFBundleVersion`, which
must increase monotonically, and *displays* `CFBundleShortVersionString`. Both are currently
typed into `Info.plist` by hand. `make release VERSION=0.2.0` stamps both with `PlistBuddy`,
so the version exists in one place: the command that was run.

**The pipeline moves to `Tools/release.sh`.** Build → embed → sign inside-out → notarize →
staple → zip → generate and sign the appcast → commit it → tag → `gh release create`. That
is past the point where a `Makefile` target can carry error handling and comments; the
`Makefile` calls the script.

---

## What the user sees

**"Check for Updates…"** goes in the app menu via the existing
`CommandGroup(after: .appInfo)`, and in the menu bar extra.

**Sparkle must not ask its first-launch question.** By default it shows its own "check
automatically?" dialog the first time the app runs — which is exactly when the onboarding
wizard is on screen. Two prompts competing on first launch is the experience the wizard
exists to prevent. Setting `SUEnableAutomaticChecks` explicitly stops it asking.

That means we choose the default, so it is **on, daily, and stated out loud**: the Done step
of onboarding gains a line saying Blurt checks for updates and where to turn it off. A
toggle, a "Check Now" button and the last-checked time go in Settings.

### Accepted mismatch

Sparkle's update window is standard AppKit and will look nothing like the rest of the app —
no brushed panel, no lamps, plain system chrome. `SPUUserDriver` allows supplying custom UI,
but that means reimplementing release-notes rendering, download progress and the install
prompt in the equipment language.

Accepted as-is. It is a window seen a handful of times a year and it looks the way macOS
updates are supposed to look. Revisit once the flow works, not before.

---

## Keys

`generate_keys` produces an EdDSA keypair. The **private key lives in the login keychain** —
never on disk, never in the repo. The public key goes in `Info.plist`.

This is what makes public hosting safe, and it is worth being explicit about: making the
repo public did not weaken update security. The updater carries no credentials, so the
appcast and payload were always going to be publicly fetchable. What stops someone serving a
malicious build is that every update is EdDSA-signed and Sparkle refuses anything that fails
verification. Someone who compromised the repo outright still could not ship a signed
update. **The signature is the security boundary; access control never was.**

**Losing the private key is unrecoverable.** Every existing install carries the matching
public key and will reject anything signed with a new one — the only recourse would be
asking every user to download a fresh build by hand. Export it with `generate_keys -x` and
store it somewhere that survives a disk failure.

`.gitignore` gains `*.pem` and `sparkle_priv*` so an exported key cannot be committed by
accident — the scan before going public found no credential files in history, and that
should stay true.

---

## Testing

Sparkle's logic is Sparkle's to test. Ours is the release pipeline, and it is only provable
end to end:

1. `make release VERSION=0.1.1`
2. Install `0.1.0` on a second machine
3. Check for updates → downloads, installs, relaunches
4. Confirm the relaunched app reports `0.1.1`

**The negative test matters more than the happy path.** Tamper with the zip after signing,
publish that, and confirm Sparkle refuses it. A silently misconfigured signature check
passes the happy path and teaches you nothing; this is the only test that proves the
boundary above actually exists.

No CI changes. The appcast is not code, and releases run locally by design.

---

## Open

- ~~Exact path to `generate_appcast` and `generate_keys`~~ — resolved. Sparkle 2.9.6 puts
  them at `$SCRATCH/artifacts/sparkle/Sparkle/bin/`, and the framework at
  `$SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/`. Both are
  `Makefile` variables now.
- Whether release signing eventually moves to GitHub Actions. Deferred deliberately: it
  would require the Developer ID certificate, its password, the notarization credential and
  the EdDSA private key all living in GitHub secrets. Worth revisiting once the local flow
  is proven.
