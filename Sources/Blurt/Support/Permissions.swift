import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// Blurt needs two grants, and neither can be worked around:
/// - **Microphone** — obviously.
/// - **Accessibility** — for both the `CGEventTap` (hotkey) and the AX text insert.
///
/// Accessibility has no programmatic request; the OS only shows the prompt, and the user
/// must toggle it in System Settings. TCC also keys on the code signature, so re-signing
/// the app resets the grant.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Shows the system Accessibility prompt if the app isn't yet trusted.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // Spelled out rather than using `kAXTrustedCheckOptionPrompt`, which imports as a
        // mutable global and so isn't usable from concurrency-checked code.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Wedged grant recovery

    /// Clears this app's Accessibility row and relaunches so macOS asks again.
    ///
    /// TCC stores a code-signing *requirement* per entry. When the stored requirement stops
    /// matching the binary, the row goes stale and the symptom lies: System Settings shows
    /// the switch as **on** while `AXIsProcessTrusted()` stays false, and toggling it off and
    /// on changes nothing, because the stale row — not the switch — is the problem. Deleting
    /// the row and re-granting is the only fix.
    ///
    /// Two things here are not stylistic:
    ///
    /// - **The bundle ID is always passed, and this refuses to run without one.** A bare
    ///   `tccutil reset Accessibility` wipes the Accessibility grant for *every app on the
    ///   machine*. The argument list must never be reachable in a state where that is what
    ///   gets executed.
    /// - **The relaunch is required, not a nicety.** TCC's answer is cached for the life of
    ///   the process, so a reset without a restart leaves this process just as untrusted as
    ///   before, and the user watches the button do nothing.
    @discardableResult
    static func resetAccessibilityGrantAndRelaunch() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            Log.app.error("Refusing to run tccutil: no bundle identifier to scope it to")
            return false
        }

        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleID]
        do {
            try reset.run()
            reset.waitUntilExit()
        } catch {
            Log.app.error("tccutil failed to launch: \(error.localizedDescription)")
            return false
        }
        guard reset.terminationStatus == 0 else {
            Log.app.error("tccutil exited \(reset.terminationStatus) for \(bundleID)")
            return false
        }
        Log.app.info("Reset Accessibility for \(bundleID) — relaunching")

        // `open -n` is a separate process, so it outlives this one and can bring the new
        // instance up after we're gone. Spawning it and then terminating is the whole dance.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", Bundle.main.bundleURL.path]
        try? relaunch.run()

        NSApp.terminate(nil)
        return true
    }
}
