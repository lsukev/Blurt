import BlurtFormatting
import BlurtInput
import SwiftUI

/// Settings — hotkey and model, per the brief. Opens on ⌘, via the standard `Settings` scene,
/// so the system wires up the menu item and the shortcut.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.wide) {
                panel(label: "Push to talk") {
                    BindingPicker(controller: controller)
                }

                panel(label: "Tone") {
                    VStack(alignment: .leading, spacing: DS.Space.snug) {
                        HStack(spacing: DS.Space.snug) {
                            ForEach(ToneMode.allCases, id: \.self) { tone in
                                TransportKey(
                                    title: tone.displayName,
                                    isEngaged: settings.toneMode == tone,
                                    engagedColor: DS.Color.ink
                                ) {
                                    settings.toneMode = tone
                                }
                                .background {
                                    if settings.toneMode == tone {
                                        RoundedRectangle(cornerRadius: DS.Radius.control)
                                            .fill(DS.Color.selection)
                                    }
                                }
                            }
                            Spacer()
                        }
                        Text(settings.toneMode.detail)
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.inkSecondary)
                        // Tone is a no-op without the model: the rule pass cannot rewrite.
                        if !settings.smartCleanup || !FoundationModelFormatter.isAvailable {
                            Text("Tone needs smart cleanup, which is off or unavailable.")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.inkSecondary)
                        }
                    }
                }

                panel(label: "Model") {
                    HStack(spacing: DS.Space.snug) {
                        ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                            TransportKey(
                                title: choice == .apple ? "Apple" : "Parakeet",
                                isEngaged: settings.engine == choice,
                                engagedColor: DS.Color.ink
                            ) {
                                settings.engine = choice
                            }
                            .background {
                                if settings.engine == choice {
                                    RoundedRectangle(cornerRadius: DS.Radius.control)
                                        .fill(DS.Color.selection)
                                }
                            }
                        }
                    }
                    note(settings.engine == .apple
                        ? "Apple's on-device transcriber. Streams text while you speak; no download."
                        : "Parakeet on the Neural Engine. Resolves on release; ~470 MB model.")
                }

                panel(label: "Cleanup") {
                    Toggle(isOn: $settings.cleanupEnabled) {
                        Silkscreen(text: "Clean up transcripts")
                    }
                    .toggleStyle(.switch)
                    note("Strips fillers, fixes spacing and punctuation. The dictionary's "
                        + "corrections run either way.")
                }

                Spacer()
            }
            .padding(DS.Space.panel)
        }
        .frame(width: 520, height: 460)
    }

    private func panel<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Silkscreen(text: label, large: true)
            content()
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedPanel())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
