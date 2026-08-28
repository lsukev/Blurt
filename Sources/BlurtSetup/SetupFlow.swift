import Foundation

/// The first-run setup flow, with none of the machinery that makes it happen.
///
/// This target exists for the same reason `BlurtDictionary` does: the decisions here are
/// worth testing, and the code that *acts* on them — TCC, event taps, System Settings — is
/// not testable at all. Everything in this file is platform-neutral and pure, so it builds
/// and runs on a CI machine that has neither macOS 26 nor a microphone.
///
/// The side effects live in `OnboardingModel` in the app target, which owns one of these.

public enum SetupStep: Int, CaseIterable, Sendable, Equatable {
    case welcome, accessibility, microphone, key, tryIt, done

    public var title: String {
        switch self {
        case .welcome: "Welcome"
        case .accessibility: "Accessibility"
        case .microphone: "Microphone"
        case .key: "Key"
        case .tryIt: "Try it"
        case .done: "Done"
        }
    }

    /// The two steps whose completion is a fact about the system rather than a fact about
    /// how far the user has walked.
    public var requiredGrant: Grant? {
        switch self {
        case .accessibility: .accessibility
        case .microphone: .microphone
        default: nil
        }
    }

    public enum Grant: Sendable, Equatable { case accessibility, microphone }
}

public struct SetupFlow: Sendable, Equatable {
    public private(set) var step: SetupStep
    /// True once the user has left setup, by finishing or by skipping out of it.
    public private(set) var isFinished: Bool

    public init(step: SetupStep = .welcome, isFinished: Bool = false) {
        self.step = step
        self.isFinished = isFinished
    }

    // MARK: - Navigation

    /// Moves to the next step, or finishes if there isn't one.
    ///
    /// Advancing off the end finishes rather than trapping: `Step(rawValue:)` returning nil
    /// is the only signal that the last step is done, and treating it as an error would
    /// make the final "Start using Blurt" button the one control that can't work.
    public mutating func advance() {
        guard let next = SetupStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    public mutating func go(to step: SetupStep) {
        self.step = step
    }

    public mutating func finish() {
        isFinished = true
    }

    // MARK: - Lamps

    /// Whether a step's lamp is lit, given what the system actually grants.
    ///
    /// The two permission steps report the grant, not the position. Walking past
    /// Accessibility with Skip leaves its lamp dark even though you're now three steps
    /// further on — which is the truth, and is what the deck's banner is about. Lighting it
    /// by position would make the rail claim a permission the app doesn't have.
    public func isLampLit(
        for step: SetupStep,
        accessibility: Bool,
        microphone: Bool
    ) -> Bool {
        switch step.requiredGrant {
        case .accessibility: accessibility
        case .microphone: microphone
        case nil: step.rawValue < self.step.rawValue
        }
    }

    // MARK: - Wedged-grant policy

    /// Whether to offer the TCC reset.
    ///
    /// There is no way to detect the stale-row state directly: `AXIsProcessTrusted()`
    /// returns false for a wedged grant in exactly the same way it does for a user who
    /// simply hasn't gone and switched it on yet. So the trigger is deliberately
    /// circumstantial — the user was sent to System Settings, enough time has gone by, and
    /// the grant still isn't there.
    ///
    /// The threshold is long on purpose. Telling someone they have a problem while they are
    /// still reading the pane is worse than saying nothing, because the fix it offers is
    /// destructive-looking and they haven't earned the fright.
    public static func shouldOfferReset(
        promptedAt: Date?,
        now: Date,
        isGranted: Bool,
        currentStep: SetupStep,
        threshold: TimeInterval = 25
    ) -> Bool {
        guard !isGranted else { return false }
        guard currentStep == .accessibility else { return false }
        guard let promptedAt else { return false }
        return now.timeIntervalSince(promptedAt) >= threshold
    }
}
