import BlurtInput
import SwiftUI

/// Choosing what you hold to dictate.
///
/// Two ways in, because the two audiences differ. A row of presets covers the keys that are
/// actually good at this — nothing types them and nothing else wants them — and a capture
/// button honours "any key or button" for anyone who has a spare thumb button or a keyboard
/// with F13 on it.
///
/// The warning below the readout is the whole reason capture is safe to offer. A plain key
/// is swallowed system-wide while Blurt runs, and that is worth knowing *before* you bind
/// Space, not after.
struct BindingPicker: View {
    let controller: DictationController

    @State private var settings = Settings.shared
    @State private var recorder = BindingRecorder()
    @State private var captureFailed = false

    /// The bindings worth suggesting: right-hand modifiers nothing else reaches for.
    private static let presets: [PushToTalkBinding] = [
        .modifier(.rightOption), .modifier(.rightCommand),
        .modifier(.fn), .modifier(.rightControl),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            HStack(spacing: DS.Space.snug) {
                ForEach(Self.presets, id: \.self) { preset in
                    presetKey(preset)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: DS.Space.snug) {
                TransportKey(
                    title: recorder.isRecording ? "Listening…" : "Press any key…",
                    isEngaged: recorder.isRecording,
                    engagedColor: DS.Color.ink
                ) {
                    recorder.isRecording ? recorder.cancel() : beginCapture()
                }
                if recorder.isRecording {
                    TransportKey(title: "Cancel") { recorder.cancel() }
                        .opacity(0.55)
                }
                Spacer(minLength: 0)
            }

            DeckWindow {
                HStack(spacing: DS.Space.base) {
                    Lamp(color: DS.Color.statusLamp, isLit: controller.state.isActive)
                    VStack(alignment: .leading, spacing: DS.Space.hair) {
                        Silkscreen(
                            text: recorder.isRecording
                                ? "Press the key or button you want"
                                : "Bound to",
                            color: DS.Color.inkOnDeck.opacity(0.6)
                        )
                        Text(settings.pushToTalkBinding.displayName)
                            .font(DS.Font.counter)
                            .foregroundStyle(DS.Color.inkOnDeck)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.base)
            }

            if let warning = settings.pushToTalkBinding.warning {
                Well {
                    HStack(alignment: .top, spacing: DS.Space.snug) {
                        Lamp(color: DS.Color.record, isLit: true)
                            .padding(.top, DS.Space.tight)
                        Text(warning)
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.inkOnDeck)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(DS.Space.base)
                }
                .transition(.opacity)
            }

            if captureFailed {
                Text("Blurt needs Accessibility permission to watch for a key.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkSecondary)
            }
        }
        .animation(DS.Motion.panel, value: settings.pushToTalkBinding)
        .animation(DS.Motion.panel, value: recorder.isRecording)
        // Leaving the panel mid-capture would otherwise strand a wide-open tap.
        .onDisappear { recorder.cancel() }
    }

    private func presetKey(_ preset: PushToTalkBinding) -> some View {
        let isSelected = settings.pushToTalkBinding == preset
        return VStack(spacing: DS.Space.tight) {
            Lamp(color: DS.Color.statusLamp, isLit: isSelected)
            Button { apply(preset) } label: {
                KeyCap(glyph: preset.displayName, width: 74, height: 34)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DS.Radius.control)
                                .strokeBorder(DS.Color.selectionEdge, lineWidth: DS.Border.bevel)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func beginCapture() {
        captureFailed = !recorder.start { binding in
            apply(binding)
        }
    }

    private func apply(_ binding: PushToTalkBinding) {
        settings.pushToTalkBinding = binding
        // The tap's event mask is derived from the binding, so rebinding rebuilds it.
        controller.reloadHotkey()
    }
}
