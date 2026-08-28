import AppKit
import Foundation
import Sparkle

/// `Blurt --check-updates`: ask the feed what it has, print the answer, exit.
///
/// Exists because the alternative was claiming updates work without having seen one found.
/// A scheduled background check leaves almost no evidence — `SULastCheckTime` moves whether
/// or not anything was found — and the user-initiated path goes through a menu item that
/// cannot be driven from a terminal.
///
/// `checkForUpdateInformation()` is the headless variant: it fetches and evaluates the
/// appcast, calls the delegate with what it found, and shows no UI. Exactly what a
/// diagnostic wants, and exactly what a release pipeline should run against a live feed
/// before believing it published something installable.
@MainActor
final class UpdateProbe: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var finished = false

    static func run() -> Never {
        let probe = UpdateProbe()
        probe.start()
        // Sparkle's fetch is async on the run loop; the delegate callbacks exit the process.
        RunLoop.main.run(until: .distantFuture)
        fatalError("unreachable")
    }

    private func start() {
        let driver = SPUUserDriverStub()
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: self
        )
        self.updater = updater

        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        print("\nBlurt --check-updates")
        print("  installed  \(short) (build \(build))")
        print("  feed       \(feed)")

        do {
            try updater.start()
        } catch {
            finish("  ERROR      updater failed to start: \(error.localizedDescription)", code: 2)
        }
        updater.checkForUpdateInformation()

        // A hung network call should not hang a diagnostic.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.finish("  ERROR      timed out after 30s", code: 2)
        }
    }

    private func finish(_ message: String, code: Int32) {
        guard !finished else { return }
        finished = true
        print(message)
        print("")
        exit(code)
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        let build = item.versionString
        MainActor.assumeIsolated {
            finish("  FOUND      \(version) (build \(build)) — \(item.fileURL?.absoluteString ?? "no enclosure")",
                   code: 0)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        MainActor.assumeIsolated {
            finish("  NONE       no applicable update — \(error.localizedDescription)", code: 0)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        MainActor.assumeIsolated {
            finish("  ERROR      \(error.localizedDescription)", code: 2)
        }
    }
}

/// Sparkle requires a user driver even for a headless check. This one refuses to show
/// anything, which is the point.
private final class SPUUserDriverStub: NSObject, SPUUserDriver {
    /// Never reached in practice — `SUEnableAutomaticChecks` in Info.plist means Sparkle
    /// never asks. Answered anyway, and answered "no", because a probe must not change the
    /// user's settings as a side effect of running.
    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.dismiss) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.dismiss)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                          acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}
