import BlurtFormatting
import BlurtInput
import Foundation
import Observation

/// Which speech engine transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet

    var displayName: String {
        switch self {
        case .apple: "Apple (streaming)"
        case .parakeet: "Parakeet (batch)"
        }
    }

    /// Apple shows text while you talk; Parakeet only resolves on release.
    var showsLiveText: Bool { self == .apple }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    /// What you hold to dictate — a modifier, any key, or a mouse button.
    var pushToTalkBinding: PushToTalkBinding {
        didSet { defaults.set(pushToTalkBinding.storageValue, forKey: Keys.pushToTalkKey) }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// Run every engine on each recording and show them side by side, instead of
    /// transcribing with one. Nothing is typed into the focused app in this mode.
    var compareMode: Bool {
        didSet { defaults.set(compareMode, forKey: Keys.compareMode) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// How much licence cleanup has to change your words. `.asSpoken` never rewrites.
    var toneMode: ToneMode {
        didSet { defaults.set(toneMode.rawValue, forKey: Keys.toneMode) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// Whether first-run setup has been seen through to the end.
    ///
    /// Deliberately separate from whether the grants are actually held. Conflating the two
    /// is wrong in both directions: someone who revokes Accessibility three weeks from now
    /// should get a banner, not a welcome wizard, and someone who quit setup halfway should
    /// not be dropped into a deck that silently does nothing.
    var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Keys.hasCompletedSetup) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkKey = "pushToTalkKey"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let engine = "engine"
        static let smartCleanup = "smartCleanup"
        static let toneMode = "toneMode"
        static let compareMode = "compareMode"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    private init() {
        // The key stays "pushToTalkKey" so installs from before bindings existed keep their
        // choice: PushToTalkBinding parses the three bare strings those versions wrote.
        let raw = defaults.string(forKey: Keys.pushToTalkKey) ?? ""
        pushToTalkBinding = PushToTalkBinding(storageValue: raw) ?? .default
        // Apple by default: no download, no dependency, live text while speaking.
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        // On by default: it is the only pass that removes real filler, applies spoken
        // self-corrections, and can fix a name the engine nearly heard. The rule pass alone
        // strips six interjections. Falls back to the rules wherever Apple Intelligence
        // isn't available, so the default is safe on machines that can't run it.
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? true
        toneMode = ToneMode(rawValue: defaults.string(forKey: Keys.toneMode) ?? "") ?? .default
        compareMode = defaults.object(forKey: Keys.compareMode) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: Keys.hasCompletedSetup)
    }
}
