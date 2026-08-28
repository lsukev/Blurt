import AVFoundation
import AppKit
import BlurtSetup
import Foundation
import Observation

/// First-run setup: the side effects.
///
/// The decisions — step order, which lamps are lit, when the TCC reset is worth offering —
/// live in `BlurtSetup.SetupFlow`, where they can be tested without macOS 26, a microphone
/// or a TCC database. This type owns one of those and does the things it cannot: prompting,
/// opening System Settings, running `tccutil`, relaunching.
///
/// Two rules shape the flow, and both are enforced in `SetupFlow` rather than here:
///
/// - **Grants advance it; buttons don't.** No "Next" after a permission step — the lamp
///   lighting *is* the confirmation.
/// - **Nothing traps you.** Every step skips through to the deck, which shows a banner.
@MainActor
@Observable
final class OnboardingModel {
    typealias Step = SetupStep

    private var flow = SetupFlow()

    var step: Step { flow.step }

    /// When the user was last sent to System Settings, which is what makes the wedged-grant
    /// offer possible to reason about. Nil until they've actually been sent.
    private var accessibilityPromptedAt: Date?
    private(set) var accessibilityLooksStuck = false

    private let permissions = PermissionMonitor.shared
    @ObservationIgnored private var stuckTask: Task<Void, Never>?

    // MARK: - Navigation

    func advance() {
        flow.advance()
        if flow.isFinished { commitCompletion() }
    }

    func go(to step: Step) {
        flow.go(to: step)
    }

    /// Leaves setup early. The deck's banner takes over from here.
    func skipToApp() {
        Log.app.info("Setup skipped at step \(self.flow.step.title, privacy: .public)")
        finish()
    }

    func finish() {
        flow.finish()
        commitCompletion()
    }

    private func commitCompletion() {
        stuckTask?.cancel()
        Settings.shared.hasCompletedSetup = true
    }

    /// Re-runs setup from the top, for the menu's "Run Setup Again…".
    static func restart() {
        Settings.shared.hasCompletedSetup = false
    }

    /// Whether a step's lamp is lit. Delegates to `SetupFlow` so the rule — permission
    /// lamps report the grant, not how far you've walked — is stated once and tested.
    func isLampLit(for step: Step) -> Bool {
        flow.isLampLit(
            for: step,
            accessibility: permissions.accessibility,
            microphone: permissions.microphone
        )
    }

    // MARK: - Accessibility

    /// Puts Blurt in the Accessibility list, *then* opens the pane.
    ///
    /// Order matters and is easy to get backwards: until `AXIsProcessTrustedWithOptions` has
    /// run with the prompt option the app isn't in that list at all, and the user arrives at
    /// a pane with nothing to switch on.
    func requestAccessibility() {
        Permissions.promptForAccessibility()
        Permissions.openAccessibilitySettings()
        accessibilityPromptedAt = Date()
        armStuckTimer()
    }

    func recoverWedgedAccessibility() {
        Permissions.resetAccessibilityGrantAndRelaunch()
    }

    private func armStuckTimer() {
        stuckTask?.cancel()
        accessibilityLooksStuck = false
        stuckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            while !Task.isCancelled {
                guard let self else { return }
                self.accessibilityLooksStuck = SetupFlow.shouldOfferReset(
                    promptedAt: self.accessibilityPromptedAt,
                    now: Date(),
                    isGranted: self.permissions.accessibility,
                    currentStep: self.flow.step
                )
                if self.accessibilityLooksStuck {
                    Log.app.info("Accessibility still not granted after prompt — offering reset")
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Called by the view when `PermissionMonitor.accessibility` flips true. Driven from
    /// there rather than from a callback here so that the app delegate — which also needs
    /// this transition, to arm the event tap — isn't competing for one closure slot.
    func accessibilityDidLand() {
        stuckTask?.cancel()
        accessibilityLooksStuck = false
        if flow.step == .accessibility { advance() }
    }

    // MARK: - Microphone

    /// Asks for the microphone, falling back to System Settings when macOS won't ask.
    ///
    /// A previously-denied microphone makes `requestAccess` return false immediately without
    /// showing anything — macOS only ever asks once. Without this fallback the button looks
    /// broken, which is the worst of the available outcomes.
    func requestMicrophone() async {
        let alreadyDecided = AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined
        let granted = await Permissions.requestMicrophone()
        permissions.refresh()

        if granted {
            if flow.step == .microphone { advance() }
        } else if alreadyDecided {
            Log.app.info("Microphone previously denied — sending the user to Settings")
            Permissions.openMicrophoneSettings()
        }
    }
}
