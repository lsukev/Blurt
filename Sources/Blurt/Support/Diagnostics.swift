import AVFoundation
import AppKit
import BlurtDictionary
import BlurtFormatting
import BlurtInput
import Foundation

/// `Blurt --diagnose`: print what the app can see about itself, then exit.
///
/// The macOS counterpart to the Windows app's `--selftest`, and it exists for the same
/// reason: the questions that come up when something isn't working — is the model actually
/// available, did Accessibility really take, which engine is live, did the dictionary load —
/// are all answerable in-process and otherwise get answered by handing someone a shell
/// incantation and interpreting the output for them.
///
/// It reports what *Blurt* sees, which is the thing that matters. A preference file can say
/// Apple Intelligence was declined while `SystemLanguageModel` reports something else; only
/// one of those decides whether cleanup works.
///
/// Nothing here prompts. `AXIsProcessTrusted()` and `AVCaptureDevice.authorizationStatus`
/// both report without asking, so running this never puts a dialog in front of someone who
/// only wanted to know the state.
///
/// **Permissions cannot be read from a terminal.** TCC attributes a directly-exec'd process
/// to its *responsible* parent — the terminal — and answers on that process's behalf, so
/// both grants read as missing however thoroughly they were granted. Measured: the same
/// binary launched by LaunchServices arms its event tap while a shell-exec'd copy of it
/// reports Accessibility missing. So this reports permissions only when launched properly,
/// says why when it can't, and points at the menu item instead.
///
/// `open -a Blurt --args --diagnose` is *not* the answer, and was tried: exiting during
/// launch breaks the LaunchServices handshake and the whole thing fails with -600. The menu
/// item is the way to get permissions into the report — the app is already running, already
/// attributed to itself, and already has the answer.
@MainActor
enum Diagnostics {

    /// LaunchServices-launched apps are reparented to launchd; anything else was exec'd by
    /// a shell, and TCC will answer for that shell rather than for us.
    static var canReadPermissions: Bool { getppid() == 1 }

    /// Builds the report. `--diagnose` from a terminal cannot read permissions; the menu
    /// item can, because the running app is attributed to itself.
    static func report() -> (text: String, blockers: [String]) {
        var blockers: [String] = []
        var out = "\nBlurt --diagnose\n"

        // MARK: Identity
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        out += section("build", [
            ("version", "\(short) (\(build))"),
            ("bundle", Bundle.main.bundleIdentifier ?? "?"),
            ("path", Bundle.main.bundleURL.path),
            ("macOS", "\(ProcessInfo.processInfo.operatingSystemVersionString) · \(machine())"),
        ])

        // MARK: Permissions
        if canReadPermissions {
            let ax = Permissions.hasAccessibility
            let mic = Permissions.hasMicrophone
            if !ax { blockers.append("Accessibility is not granted — the hotkey cannot arm and text cannot be inserted.") }
            if !mic { blockers.append("Microphone is not granted — nothing can be recorded.") }
            out += section("permissions", [
                ("accessibility", ax ? "granted" : "MISSING"),
                ("microphone", mic ? "granted" : "MISSING"),
            ])
        } else {
            // Reporting the values here would be worse than omitting them: they would both
            // read MISSING on a machine where both are granted.
            out += section("permissions", [
                ("accessibility", "not readable from a terminal"),
                ("microphone", "not readable from a terminal"),
                ("why", "TCC answers for the parent process, not for Blurt"),
                ("instead", "menu bar ▸ Copy Diagnostics — includes permissions"),
            ])
        }

        // MARK: Cleanup
        let settings = Settings.shared
        let modelReason = FoundationModelFormatter.unavailableReason
        let modelState = modelReason.map { "unavailable — \($0)" } ?? "available"
        var cleanupRows: [(String, String)] = [
            ("cleanup", settings.cleanupEnabled ? "on" : "off"),
            ("on-device model", modelState),
        ]
        if settings.cleanupEnabled {
            let smart = settings.smartCleanup
            cleanupRows.append((
                "smart cleanup",
                smart ? (modelReason == nil ? "on" : "on, falling back to rules") : "off"
            ))
            cleanupRows.append((
                "tone",
                settings.toneMode.displayName
                    + (smart && modelReason == nil ? "" : "  (inert without the model)")
            ))
        }
        out += section("cleanup", cleanupRows)

        // MARK: Input
        let binding = settings.pushToTalkBinding
        out += section("input", [
            ("push-to-talk", binding.displayName),
            ("tap requests", tapDescription(for: binding)),
            ("suppresses it", binding.consumesEvent ? "yes" : "no"),
        ] + (binding.warning.map { [("note", $0)] } ?? []))

        // MARK: Speech
        out += section("speech", [
            ("engine", settings.compareMode ? "compare mode — every engine, nothing injected"
                                            : settings.engine.displayName),
            ("parakeet models", ParakeetModels.isDownloaded ? "downloaded" : "not downloaded"),
        ])

        // MARK: Dictionary
        let entries = DictionaryStore.shared.entries
        let enabled = entries.filter(\.isEnabled).count
        let bias = DictionaryStore.shared.biasPhrases.count
        out += section("dictionary", [
            ("entries", "\(enabled) enabled of \(entries.count)"),
            ("engine bias", "\(bias) of \(DictionaryCorrector.biasLimit) sent to the engine"),
            ("file", DictionaryStore.fileURL.path),
        ])

        // MARK: Updates
        out += section("updates", [
            ("feed", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "not configured"),
            ("signing key", Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
                ? "present" : "MISSING — updates cannot be verified"),
            ("automatic", UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool
                ?? (Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false)
                ? "on" : "off"),
        ])

        // MARK: Verdict
        out += "\n"
        if blockers.isEmpty {
            out += canReadPermissions
                ? "OK — Blurt can dictate as configured.\n"
                : "OK so far — but permissions were not checked. See above.\n"
            if modelReason != nil {
                // Not a blocker: the rule pass still cleans up. But it is the difference
                // between "tidy" and "the features you were promised", so it is said.
                out += "Note: cleanup is the rule-based pass only. Tone and dictionary-aware\n"
                out += "      name correction need the on-device model.\n"
            }
        } else {
            out += "BLOCKED\n"
            for blocker in blockers { out += "  · \(blocker)\n" }
        }
        out += "\n"

        return (out, blockers)
    }

    /// The `--diagnose` entry point: print and exit.
    static func run() -> Int32 {
        let (text, blockers) = report()
        FileHandle.standardOutput.write(Data(text.utf8))
        return blockers.isEmpty ? 0 : 1
    }

    /// The menu entry point. Same report, and this one can see the permissions.
    static func copyToPasteboard() {
        let (text, _) = report()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Log.app.info("diagnostics copied to the pasteboard")
    }

    // MARK: - Rendering

    private static func section(_ title: String, _ rows: [(String, String)]) -> String {
        var text = "\n\(title)\n"
        let width = rows.map(\.0.count).max() ?? 0
        for (label, value) in rows {
            text += "  \(label.padding(toLength: width, withPad: " ", startingAt: 0))  \(value)\n"
        }
        return text
    }

    private static func tapDescription(for binding: PushToTalkBinding) -> String {
        let names = binding.requiredEventTypes.sorted().map { type -> String in
            switch type {
            case 10: "keyDown"
            case 11: "keyUp"
            case 12: "flagsChanged"
            case 25: "otherMouseDown"
            case 26: "otherMouseUp"
            default: "type \(type)"
            }
        }
        // Worth showing: it is how you can see that a modifier binding never asks for
        // keyboard events, which is the privacy property the tap scoping exists for.
        return names.joined(separator: ", ")
    }

    private static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
