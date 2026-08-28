EXEC     := Blurt
CONFIG   := debug

## Build products live OUTSIDE this directory, for the same reason the .app does.
##
## ~/Desktop is iCloud/file-provider synced, and the provider mutates files inside
## .build while the compiler is using them — producing "input file was modified during
## the build" on random object files, and occasionally a wedged swift-frontend stuck at
## 0% CPU. Moving the scratch path to ~/Library/Caches (never synced) removes the race.
SCRATCH  := $(HOME)/Library/Caches/BlurtBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)

## The bundle is assembled and signed OUTSIDE this directory on purpose.
##
## This tree lives under ~/Desktop, which is iCloud/file-provider synced. The provider
## stamps com.apple.FinderInfo onto files inside an .app faster than we can strip them,
## and codesign hard-refuses anything carrying them ("resource fork, Finder information,
## or similar detritus not allowed"). `xattr -cr` immediately before signing is not enough
## — the provider re-stamps in between. Staging in ~/Library/Caches sidesteps it entirely.
STAGE    := $(HOME)/Library/Caches/BlurtBuild
APPNAME  := Blurt.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys the Accessibility grant to the code signature, so an ad-hoc signature — which
## changes on every build — makes the user re-grant after every `make`. Signing with a
## stable Developer ID keeps the identity constant and the grant sticky. Falls back to
## ad-hoc ("-") on a machine without the cert.
## Sparkle arrives as an XCFramework binary artifact, extracted under the scratch path.
SPARKLE_FRAMEWORK := $(SCRATCH)/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
SPARKLE_BIN       := $(SCRATCH)/artifacts/sparkle/Sparkle/bin

SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build app run install clean icon notarize release

## Timestamping is a network round-trip to Apple's timestamp server, which is wasted time
## on every local build — but notarization *requires* a secure timestamp, so the notarize
## target turns it back on rather than everyone paying for it always.
TIMESTAMP ?= --timestamp=none

## The keychain profile holding the notarization credential. Created once, by hand:
##
##   xcrun notarytool store-credentials blurt-notary \
##     --apple-id <your-apple-id> --team-id $(TEAM_ID) --password <app-specific-password>
##
## The credential lives in the keychain, never in this file.
NOTARY_PROFILE ?= blurt-notary
TEAM_ID        := 38ZD3H23A8
DIST           := dist

all: app

## The rpath is what lets the executable find the embedded Sparkle at runtime. It lives
## here rather than in Package.swift as `linkerSettings`: in the manifest it would also
## apply during `swift test` in CI, which doesn't link Sparkle and doesn't need it, and
## `.unsafeFlags` in a manifest spreads to anything depending on the package.
##
## Without it the app builds, signs, notarizes — and then dies at launch with a dyld error.
build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)" \
		-Xlinker -rpath -Xlinker @executable_path/../Frameworks

## Regenerates AppIcon.icns from Tools/makeicon.swift. Not a dependency of `app` — the
## icon rarely changes and rendering 10 PNGs on every build is wasted time.
icon:
	@swift Tools/makeicon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CONTENTS)/Frameworks"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@# SwiftPM links frameworks but does not embed them — that is Xcode's job, and this
	@# bundle is assembled by hand. Copy it in ourselves or the app cannot start.
	@cp -R "$(SPARKLE_FRAMEWORK)" "$(CONTENTS)/Frameworks/"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Belt and braces: the staging dir isn't synced, but the copied binary can still carry
	@# xattrs inherited from the synced .build directory.
	@xattr -cr "$(BUNDLE)"
	@# Signing runs INSIDE-OUT. Sparkle's framework carries its own executables — the
	@# updater app, the installer, XPC services — and each must be signed before the
	@# framework, which must be signed before the app. Sign the app first and notarization
	@# rejects the submission with a message that blames the framework rather than the
	@# ordering. `--deep` is not a shortcut for this: it is deprecated and does not apply
	@# entitlements correctly.
	@F="$(CONTENTS)/Frameworks/Sparkle.framework"; \
	for nested in \
		"$$F/Versions/B/XPCServices/Installer.xpc" \
		"$$F/Versions/B/XPCServices/Downloader.xpc" \
		"$$F/Versions/B/Autoupdate" \
		"$$F/Versions/B/Updater.app"; do \
		[ -e "$$nested" ] && codesign --force --sign "$(SIGN_ID)" --options runtime \
			$(TIMESTAMP) "$$nested" || true; \
	done; \
	codesign --force --sign "$(SIGN_ID)" --options runtime $(TIMESTAMP) "$$F"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		$(TIMESTAMP) \
		"$(BUNDLE)"
	@codesign --verify --strict --verbose=1 "$(BUNDLE)" >/dev/null 2>&1 \
		&& echo "built $(BUNDLE)  [signed: $(SIGN_ID)]" \
		|| { echo "SIGNATURE INVALID — refusing to continue"; exit 1; }

## Only ever targets the Blurt executable — never another dictation app that happens to
## be running under a similar name.
run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Ad-hoc signatures change on every rebuild, which resets the Accessibility grant.
## Installing to /Applications keeps the path stable and makes re-granting a one-click fix.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@# $(BUNDLE) is an absolute staging path — the destination must use $(APPNAME) alone.
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

## Notarize a release build and staple Apple's ticket to it.
##
## Stapling attaches the ticket to the .app itself, so it launches on a machine that is
## offline or has never seen the app before. A zip cannot be stapled — it's only transport,
## which is why it's rebuilt from the stapled bundle afterwards rather than reused.
##
## Signing here must use a secure timestamp, hence the TIMESTAMP override; without it the
## submission is rejected before Apple even looks at the binary.
notarize:
	@$(MAKE) --no-print-directory app CONFIG=release TIMESTAMP=--timestamp
	@mkdir -p "$(DIST)"
	@rm -f "$(DIST)/$(EXEC)-submit.zip" "$(DIST)/$(EXEC).zip"
	@ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE)" "$(DIST)/$(EXEC)-submit.zip"
	@echo "submitting to Apple — this usually takes a few minutes"
	@xcrun notarytool submit "$(DIST)/$(EXEC)-submit.zip" \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple "$(BUNDLE)"
	@rm -f "$(DIST)/$(EXEC)-submit.zip"
	@ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE)" "$(DIST)/$(EXEC).zip"
	@echo "--- gatekeeper ---"
	@spctl -a -vvv -t exec "$(BUNDLE)" || true
	@echo "stapled: $(DIST)/$(EXEC).zip"

## Cut a release. The pipeline outgrew a Makefile target — it needs preflight checks and
## error handling — so it lives in Tools/release.sh and this just hands it the paths.
##
##   make release VERSION=0.4.0
release:
	@BUNDLE="$(BUNDLE)" SPARKLE_BIN="$(SPARKLE_BIN)" EXEC="$(EXEC)" DIST="$(DIST)" \
		NOTARY_PROFILE="$(NOTARY_PROFILE)" VERSION="$(VERSION)" \
		bash Tools/release.sh

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
