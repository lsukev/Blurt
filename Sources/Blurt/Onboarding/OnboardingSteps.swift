import SwiftUI

// The individual setup steps. Each owns its stage content only — the chassis, rail and step
// counter come from `OnboardingView`.

// MARK: - Shared furniture

/// A step's headline and opening paragraph.
struct StepHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text(title)
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
            Text(detail)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .lineSpacing(DS.Space.tight - DS.Space.hair)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)
        }
    }
}

/// The trailing action row. `Skip` is on every step on purpose — see `OnboardingModel`.
struct StepActions<Trailing: View>: View {
    let model: OnboardingModel
    var skipTitle = "Skip"
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Spacer()
            TransportKey(title: skipTitle) { model.skipToApp() }
                .opacity(0.55)
            trailing
        }
    }
}

/// A note in a recessed well — the secondary path on a step, for the case that goes wrong.
struct StepNote<Trailing: View>: View {
    let label: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Well {
            HStack(alignment: .center, spacing: DS.Space.roomy) {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Silkscreen(text: label, color: DS.Color.inkOnDeck)
                    Text(detail)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(DS.Space.roomy)
        }
    }
}

// MARK: - 1 · Welcome

struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "Hold a key. Talk. Let go.",
                detail: "Blurt types what you said into whatever you were already working in. "
                    + "Everything runs on this Mac — nothing you say leaves it."
            )

            gesture

            Well {
                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    Silkscreen(text: "Before you start", color: DS.Color.inkOnDeck)
                    Text("Blurt needs two permissions from macOS. It can ask for the microphone "
                        + "itself. Accessibility you have to switch on by hand — that's the one "
                        + "that takes a minute.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkOnDeck)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460, alignment: .leading)
                }
                .padding(DS.Space.roomy)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                TransportKey(title: "Begin") { model.advance() }
            }
        }
    }

    /// The whole product in three beats. This earns its place: it explains the gesture
    /// faster than any paragraph, and the gesture is the entire interaction model.
    private var gesture: some View {
        HStack(spacing: DS.Border.seam) {
            beat(label: "Hold") { KeyCap(glyph: "⌥") }
            beat(label: "Talk") { WaveformMark() }
            beat(label: "It's typed") { TypedMark() }
        }
        .background(DS.Color.seam)
        .clipShape(.rect(cornerRadius: DS.Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel)
                .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
        )
    }

    private func beat<Art: View>(label: String, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: DS.Space.base) {
            art()
                .frame(height: DS.Material.keyHeight)
            Silkscreen(text: label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.roomy)
        .background(DS.Color.panel)
    }
}

/// A key cap with a glyph on it — the physical thing you hold.
struct KeyCap: View {
    let glyph: String
    var width: CGFloat = DS.Material.keyMinWidth
    var height: CGFloat = DS.Material.keyHeight

    var body: some View {
        Text(glyph)
            .font(DS.Font.bodyEmphasis)
            .foregroundStyle(DS.Color.ink)
            .frame(width: width, height: height)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(DS.Color.cap)
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Color.panelHighlight, lineWidth: DS.Border.bevel)
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Color.seam.opacity(0.5), lineWidth: DS.Border.hairline)
                }
                .shadow(
                    color: DS.Shadow.raised.color,
                    radius: DS.Shadow.raised.radius,
                    x: DS.Shadow.raised.x,
                    y: DS.Shadow.raised.y
                )
            }
    }
}

private struct WaveformMark: View {
    private static let heights: [CGFloat] = [0.35, 0.7, 1, 0.5, 1, 0.55, 0.85, 0.35]

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { _, scale in
                Capsule()
                    .fill(DS.Color.silkscreen)
                    .frame(width: DS.Material.needleWidth + 0.5,
                           height: DS.Material.keyHeight * scale)
            }
        }
        .frame(height: DS.Material.keyHeight)
    }
}

private struct TypedMark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug - DS.Space.hair) {
            line(width: 40)
            line(width: 52)
            HStack(alignment: .bottom, spacing: DS.Space.hair) {
                line(width: 22)
                Rectangle()
                    .fill(DS.Color.ink)
                    .frame(width: DS.Border.hairline + 0.5, height: DS.Space.base)
            }
        }
        .frame(height: DS.Material.keyHeight)
    }

    private func line(width: CGFloat) -> some View {
        Capsule()
            .fill(DS.Color.silkscreen)
            .frame(width: width, height: DS.Space.hair)
    }
}

// MARK: - 2 · Accessibility

struct AccessibilityStep: View {
    let model: OnboardingModel
    let permissions: PermissionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "Switch on Accessibility",
                detail: "Blurt watches for one key, and types text for you. macOS files both of "
                    + "those under Accessibility. It's the one permission the system won't grant "
                    + "on an app's say-so — the switch has to be yours."
            )

            DeckWindow {
                VStack(alignment: .leading, spacing: DS.Space.base) {
                    HStack(spacing: DS.Space.snug) {
                        Lamp(color: DS.Color.statusLamp, isLit: permissions.accessibility)
                        Silkscreen(
                            text: permissions.accessibility ? "Granted" : "Waiting for the switch",
                            color: DS.Color.inkOnDeck.opacity(0.75)
                        )
                    }

                    Rectangle()
                        .fill(DS.Color.seam)
                        .frame(height: DS.Border.seam)

                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        statusRow("in the accessibility list", permissions.accessibility ? "yes" : "yes")
                        statusRow("event tap", permissions.accessibility ? "armed" : "not permitted")
                        statusRow("microphone", permissions.microphone ? "granted" : "not asked yet")
                    }
                }
                .padding(DS.Space.roomy)
            }

            // Only appears once the user has been sent to Settings and it still hasn't taken.
            // We can't see the stale row directly, so this is triggered by elapsed time rather
            // than by detection — see OnboardingModel.accessibilityLooksStuck.
            if model.accessibilityLooksStuck {
                StepNote(
                    label: "Switched it on and nothing happened?",
                    detail: "macOS can keep showing the switch as on while still refusing the app. "
                        + "Blurt can clear that and ask again — it will quit and reopen."
                ) {
                    TransportKey(title: "Fix it") { model.recoverWedgedAccessibility() }
                }
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            StepActions(model: model) {
                TransportKey(title: "Open System Settings") { model.requestAccessibility() }
            }
        }
        .animation(DS.Motion.panel, value: model.accessibilityLooksStuck)
    }

    /// A monospaced self-test line — how equipment reports its own state.
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.Font.counter)
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.65))
            Spacer(minLength: DS.Space.base)
            Text(value)
                .font(DS.Font.counter)
                .foregroundStyle(DS.Color.inkOnDeck)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}

// MARK: - 3 · Microphone

struct MicrophoneStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "Allow the microphone",
                detail: "This one macOS asks for directly — no trip to System Settings. Blurt "
                    + "listens only while you're holding the key, and stops the moment you let go."
            )

            Well {
                HStack(spacing: DS.Space.wide) {
                    VUMeter(level: 0, isActive: false)
                        .frame(width: 208, height: 58)
                        .opacity(0.75)
                    VStack(alignment: .leading, spacing: DS.Space.tight) {
                        Silkscreen(text: "No signal", color: DS.Color.inkOnDeck)
                        Text("The meter wakes up once macOS lets Blurt hear you.")
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.inkOnDeck.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.roomy)
            }

            // macOS only ever asks once. A user who said no previously gets nothing at all
            // from the button above, so the fallback has to be visible rather than discovered.
            StepNote(
                label: "Turned it down before?",
                detail: "macOS only asks once. If you've already said no to Blurt, the button "
                    + "won't do anything and you'll need to switch it on by hand."
            ) {
                TransportKey(title: "Settings") { Permissions.openMicrophoneSettings() }
            }

            Spacer(minLength: 0)

            StepActions(model: model) {
                TransportKey(title: "Allow microphone") {
                    Task { await model.requestMicrophone() }
                }
            }
        }
    }
}

// MARK: - 4 · Key

struct KeyStep: View {
    let model: OnboardingModel
    let controller: DictationController

    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "Choose your key",
                detail: "Hold it to dictate, let go to stop. Pick one nothing else on your Mac "
                    + "already wants."
            )

            HStack(spacing: DS.Space.roomy) {
                ForEach(PushToTalkKey.allCases, id: \.self) { candidate in
                    option(candidate)
                }
                Spacer(minLength: 0)
            }

            DeckWindow {
                HStack(spacing: DS.Space.roomy) {
                    Lamp(color: DS.Color.statusLamp,
                         isLit: controller.state.isActive,
                         size: DS.Material.lampSize * 1.6)
                    VStack(alignment: .leading, spacing: DS.Space.hair) {
                        Silkscreen(
                            text: controller.state.isActive ? "Holding — Blurt sees it" : "Hold your key to test it",
                            color: DS.Color.inkOnDeck.opacity(0.75)
                        )
                        Text(settings.pushToTalkKey.displayName)
                            .font(DS.Font.counter)
                            .foregroundStyle(DS.Color.inkOnDeck)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.roomy)
            }

            // There is no API that reports "another app also saw that keypress" — an event
            // tap sees the event either way. The rehearsal above is the detection: if a rival
            // dictation app owns this key, its HUD appears while the user is holding it.
            StepNote(
                label: "Already run another dictation app?",
                detail: "Hold the key now. If that app's window appears too, both are listening "
                    + "and they'll fight over the text — pick a different one here."
            ) {
                EmptyView()
            }

            Spacer(minLength: 0)

            StepActions(model: model) {
                TransportKey(title: "Continue") { model.advance() }
            }
        }
    }

    private func option(_ candidate: PushToTalkKey) -> some View {
        let isSelected = settings.pushToTalkKey == candidate
        return VStack(spacing: DS.Space.snug) {
            Lamp(color: DS.Color.statusLamp, isLit: isSelected)
            Button {
                settings.pushToTalkKey = candidate
                controller.reloadHotkey()
            } label: {
                KeyCap(glyph: candidate.capGlyph, width: 118, height: 56)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .strokeBorder(DS.Color.selectionEdge, lineWidth: DS.Border.bevel)
                        }
                    }
            }
            .buttonStyle(.plain)
            Silkscreen(text: candidate.displayName)
        }
    }
}

private extension PushToTalkKey {
    /// What's printed on the cap, as opposed to the sentence-shaped `displayName`.
    var capGlyph: String {
        switch self {
        case .rightOption: "⌥"
        case .fn: "fn"
        case .rightCommand: "⌘"
        }
    }
}

// MARK: - 6 · Done

struct DoneStep: View {
    let model: OnboardingModel

    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "You're set.",
                detail: "Hold \(settings.pushToTalkKey.displayName) anywhere on your Mac and talk. "
                    + "Blurt types into whatever has focus — a search field, a chat box, an editor."
            )

            DeckWindow {
                HStack(spacing: DS.Space.roomy) {
                    KeyCap(glyph: settings.pushToTalkKey.capGlyph, width: 96, height: 48)
                    VStack(alignment: .leading, spacing: DS.Space.hair) {
                        Silkscreen(text: "Your key", color: DS.Color.inkOnDeck.opacity(0.6))
                        Text("\(settings.pushToTalkKey.displayName) — hold to dictate")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkOnDeck)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.roomy)
            }

            Well {
                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    Silkscreen(text: "Two things worth knowing", color: DS.Color.inkOnDeck)
                    Text("The menu bar icon holds your settings, your word list, and everything "
                        + "you've dictated.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Nothing you say leaves this Mac. Transcription and cleanup both run "
                        + "on-device.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)
                .padding(DS.Space.roomy)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                TransportKey(title: "Start using Blurt") { model.finish() }
            }
        }
    }
}
