import AVFoundation
import AppKit
import Foundation
import Observation

/// Drives first-run setup: which step is on screen, when it advances, and what the
/// Accessibility step offers when macOS gets stubborn.
///
/// Two rules shape the whole thing:
///
/// - **Grants advance the flow; buttons don't.** There is no "Next" after a permission step.
///   The lamp lighting *is* the confirmation, so the user flips the switch, comes back, and
///   the wizard has already moved on.
/// - **Nothing traps you.** Every step can be skipped through to the deck, which shows a
///   banner instead. A wizard that holds a tester hostage over a permission is how you get
///   the app deleted rather than debugged.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, microphone, key, tryIt, done

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .accessibility: "Accessibility"
            case .microphone: "Microphone"
            case .key: "Key"
            case .tryIt: "Try it"
            case .done: "Done"
            }
        }
    }

    private(set) var step: Step = .welcome

    /// Set once the user has been sent to System Settings and the grant still hasn't landed.
    /// We cannot detect the stale-row state directly — `AXIsProcessTrusted()` reports false
    /// exactly as it would if the user had simply not done it yet. What we *can* detect is
    /// "you were sent to do this, enough time has passed, and it still isn't true", which is
    /// the honest trigger for offering the fix.
    private(set) var accessibilityLooksStuck = false

    /// True while the user is holding their push-to-talk key on the key step, so the panel
    /// can show that Blurt sees it.
    var isTestingKey = false

    private let permissions = PermissionMonitor.shared
    @ObservationIgnored private var stuckTask: Task<Void, Never>?

    /// How long to wait after sending someone to System Settings before offering the reset.
    /// Long enough that a user who is simply reading isn't told they have a problem.
    private static let stuckThreshold: Duration = .seconds(25)

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    func go(to step: Step) {
        self.step = step
    }

    /// Leaves setup early. The deck's banner takes over from here.
    func skipToApp() {
        Log.app.info("Setup skipped at step \(self.step.title, privacy: .public)")
        finish()
    }

    func finish() {
        stuckTask?.cancel()
        Settings.shared.hasCompletedSetup = true
    }

    /// Re-runs setup from the top, for the menu's "Run Setup Again…".
    static func restart() {
        Settings.shared.hasCompletedSetup = false
    }

    // MARK: - Accessibility

    /// Puts Blurt in the Accessibility list, *then* opens the pane.
    ///
    /// Order matters and is easy to get backwards: until `AXIsProcessTrustedWithOptions`
    /// has run with the prompt option, the app isn't in that list at all, and the user
    /// arrives at a pane with nothing to switch on.
    func requestAccessibility() {
        Permissions.promptForAccessibility()
        Permissions.openAccessibilitySettings()
        armStuckTimer()
    }

    func recoverWedgedAccessibility() {
        Permissions.resetAccessibilityGrantAndRelaunch()
    }

    private func armStuckTimer() {
        stuckTask?.cancel()
        accessibilityLooksStuck = false
        stuckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.stuckThreshold)
            guard let self, !Task.isCancelled else { return }
            guard !self.permissions.accessibility, self.step == .accessibility else { return }
            self.accessibilityLooksStuck = true
            Log.app.info("Accessibility still not granted after prompt — offering reset")
        }
    }

    /// Called by the view when `PermissionMonitor.accessibility` flips true. Driven from
    /// there rather than from a callback here so that the app delegate — which also needs
    /// this transition, to arm the event tap — isn't competing for one closure slot.
    func accessibilityDidLand() {
        stuckTask?.cancel()
        accessibilityLooksStuck = false
        if step == .accessibility { advance() }
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
            if step == .microphone { advance() }
        } else if alreadyDecided {
            Log.app.info("Microphone previously denied — sending the user to Settings")
            Permissions.openMicrophoneSettings()
        }
    }
}
