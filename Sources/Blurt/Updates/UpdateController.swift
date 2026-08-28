import Foundation
import Observation
import Sparkle

/// In-app updates.
///
/// A thin wrapper over `SPUStandardUpdaterController`, and deliberately thin. Sparkle owns
/// the update UI, the download, the signature check, and the part that must not be
/// hand-rolled — replacing a running `.app` atomically and relaunching it. This type exists
/// so menus and Settings have something observable to bind to, not to add behaviour.
///
/// Two things are configured in `Info.plist` rather than here, and both matter:
///
/// - `SUEnableAutomaticChecks` is set explicitly so Sparkle never asks its own first-launch
///   "check automatically?" question. That dialog would fire during the onboarding wizard,
///   which is exactly the competing-prompt experience the wizard exists to prevent.
/// - `SUPublicEDKey` is what makes public hosting safe. The feed and the payload are
///   fetchable by anyone — the updater carries no credentials, so they always were going to
///   be. What stops someone serving a malicious build is that every update is EdDSA-signed
///   with a key held only by the person cutting releases. The signature is the boundary;
///   access control never was.
@MainActor
@Observable
final class UpdateController {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    /// False while a check is already running, so the menu item can disable itself.
    private(set) var canCheck = true
    private(set) var lastCheckedAt: Date?

    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // `startingUpdater: true` begins the scheduled-check timer immediately. Safe here:
        // the first-launch consent dialog is suppressed by Info.plist, so nothing appears on
        // screen unless an update actually exists.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        lastCheckedAt = controller.updater.lastUpdateCheckDate

        // Sparkle publishes this through KVO rather than Observation, so it is bridged
        // rather than read on demand — a menu item that reads it once stays stale.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheck = updater.canCheckForUpdates
            }
        }
    }

    /// Whether Blurt checks on its own. Persisted by Sparkle, not by `Settings`.
    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var feedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—"
    }

    /// A check the user asked for. Sparkle shows its own UI from here, including telling
    /// them when they are already up to date — which a background check deliberately does
    /// not do.
    func checkForUpdates() {
        Log.app.info("checking for updates")
        controller.updater.checkForUpdates()
        lastCheckedAt = Date()
    }
}
