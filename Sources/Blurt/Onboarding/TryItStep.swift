import SwiftUI

/// The rehearsal: hold the key, talk, watch text land in a real field.
///
/// The field below is a genuine `TextField` that we take focus on, and the text arrives
/// through the ordinary dictation path — `HotkeyMonitor` → `AudioCapture` → the engine →
/// `TextFormatter` → `TextInjector`. Nothing here is special-cased.
///
/// That is the entire point of the step. `AGENTS.md` is blunt that speech → transcript →
/// injection is the one path no automated test can reach: CI can't speak and can't hold a
/// key. So this is the only place the whole chain gets exercised on the user's own hardware,
/// with their microphone, before they're alone with it. Shortcutting the injection to just
/// display `controller.transcript` would make the step look identical and prove nothing.
struct TryItStep: View {
    let model: OnboardingModel
    @Bindable var controller: DictationController

    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var didLandText: Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            StepHeader(
                title: "Say something.",
                detail: "Hold your key and talk. This runs the real thing — the same path Blurt "
                    + "uses in every other app."
            )

            instruments

            DeckWindow {
                VStack(alignment: .leading, spacing: DS.Space.snug) {
                    Silkscreen(text: "Blurt types here", color: DS.Color.inkOnDeck.opacity(0.6))

                    TextField("", text: $typed, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkOnDeck)
                        .lineLimit(2...4)
                        .focused($fieldFocused)

                    // Apple's engine streams while you're still talking; Parakeet only
                    // resolves on release. Showing the volatile text keeps the slower engine
                    // from looking like a hang.
                    if controller.state.isActive, !controller.transcript.isEmpty {
                        Text(controller.transcript)
                            .font(DS.Font.counter)
                            .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(DS.Space.roomy)
            }

            Spacer(minLength: 0)

            StepActions(model: model, skipTitle: "Skip") {
                TransportKey(title: "That worked") { model.advance() }
                    .opacity(didLandText ? 1 : 0.4)
                    .disabled(!didLandText)
            }
        }
        // The injector targets whatever holds focus system-wide, so this step only works if
        // the field actually has it. Re-assert on appear rather than trusting initial state.
        .onAppear { fieldFocused = true }
        .animation(DS.Motion.panel, value: didLandText)
    }

    private var instruments: some View {
        HStack(spacing: DS.Space.roomy) {
            VUMeter(level: controller.level, isActive: controller.state.isActive)
                .frame(width: 208, height: 58)

            Well {
                HStack(spacing: DS.Space.roomy) {
                    Lamp(color: DS.Color.record,
                         isLit: controller.state.isActive,
                         size: DS.Material.lampSize * 1.6)
                    VStack(alignment: .leading, spacing: DS.Space.hair) {
                        Silkscreen(
                            text: controller.state.isActive ? "Recording" : "Ready",
                            color: DS.Color.inkOnDeck
                        )
                        Text(controller.state.isActive ? "listening" : "hold to start")
                            .font(DS.Font.counter)
                            .foregroundStyle(DS.Color.inkOnDeck.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.roomy)
                .frame(height: 58)
            }
            .frame(maxWidth: 240)

            Spacer(minLength: 0)
        }
    }
}
