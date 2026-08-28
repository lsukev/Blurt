import AppKit
import Foundation
import Observation

/// Live state of the two grants Blurt cannot work without.
///
/// `Permissions` answers "is it granted *right now*" and nothing more, which is enough for a
/// menu that re-renders on every open but useless to a view that has to sit on screen and
/// react the moment the user flips a switch in System Settings. Neither grant has a change
/// notification — Accessibility has no API for it at all — so something has to poll, and
/// this is that something.
///
/// It replaces the `while !Permissions.hasAccessibility` loop that used to live in
/// `AppDelegate.retryActivation()`: one poller the whole app shares, rather than a private
/// one that only ever ran at launch and told the UI nothing.
@MainActor
@Observable
final class PermissionMonitor {
    static let shared = PermissionMonitor()

    private(set) var accessibility: Bool
    private(set) var microphone: Bool

    var allGranted: Bool { accessibility && microphone }

    // Deliberately no `onGranted` callback: both the app delegate (to arm the event tap) and
    // onboarding (to advance a step) need to know, and a single closure slot means whichever
    // registers second silently wins. Consumers observe `accessibility` instead — SwiftUI
    // with `.onChange`, the delegate with `withObservationTracking`.

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    private init() {
        accessibility = Permissions.hasAccessibility
        microphone = Permissions.hasMicrophone

        // Coming back from System Settings makes this app active again, which is both the
        // most likely moment for a grant to have changed and free to observe. The poll below
        // covers everything else — a user who never switches back to us, mostly.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // `queue: .main` means the main *thread*, which is not a claim Swift concurrency
            // will take our word for. `MainActor.assumeIsolated` asserts rather than checks
            // and has already taken this app down once — hop properly instead.
            Task { @MainActor in PermissionMonitor.shared.refresh() }
        }

        resumePollingIfNeeded()
    }

    /// Re-reads both grants once. Cheap; call it from anywhere a loss might have happened —
    /// a dead event tap, a failed capture, a window appearing.
    func refresh() {
        let wasAccessibility = accessibility
        accessibility = Permissions.hasAccessibility
        microphone = Permissions.hasMicrophone

        if !wasAccessibility, accessibility {
            Log.app.info("Accessibility granted")
        }
        resumePollingIfNeeded()
    }

    /// Polls while anything is missing and stops once both are held — a dictation app runs
    /// all day, and a timer that never stops is a timer that shows up in Activity Monitor.
    /// `refresh()` is how a revocation gets noticed after that, which is why the failure
    /// paths call it.
    private func resumePollingIfNeeded() {
        guard !allGranted else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }

                let wasAccessibility = self.accessibility
                self.accessibility = Permissions.hasAccessibility
                self.microphone = Permissions.hasMicrophone

                if !wasAccessibility, self.accessibility {
                    Log.app.info("Accessibility granted — hotkey can arm")
                }
                if self.allGranted {
                    self.pollTask = nil
                    return
                }
            }
        }
    }
}
