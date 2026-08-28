import BlurtFormatting
import BlurtInput
import AppKit
import SwiftUI

@main
struct BlurtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// `--diagnose` prints what Blurt can see about itself and exits without showing a
    /// window. Handled here rather than in the delegate because
    /// `applicationDidFinishLaunching` runs after the app has already activated and put a
    /// window on screen — too late to be a command-line tool.
    init() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        exit(Diagnostics.run())
    }

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // panel, and letting ⌘N spawn a second copy of a tape deck makes no sense.
        Window("Blurt", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { delegate.updates.checkForUpdates() }
                    .disabled(!delegate.updates.canCheck)
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        // Secondary now: status and the hotkey while you're working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller, updates: delegate.updates)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }

        Window("Engine comparison", id: "comparison") {
            ComparisonWindow(controller: delegate.controller)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    let updates = UpdateController()
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A regular app now: dock icon, app menu, standard windows. The HUD is still a
        // non-activating panel, so dictating into another app never steals its focus — that
        // property belongs to the panel, not to the activation policy.
        NSApp.setActivationPolicy(.regular)

        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            // Only ask outright for someone who has already been through setup and lost the
            // grant since. On a first run the wizard owns this: throwing the system dialog
            // at a user who hasn't seen the welcome screen yet is the exact experience
            // onboarding exists to replace.
            if Settings.shared.hasCompletedSetup {
                Permissions.promptForAccessibility()
            }
            // The tap can only be created once Accessibility lands, and there's no
            // notification for it — PermissionMonitor polls, we watch it.
            armHotkeyWhenPermitted()
        }

        // Write the dashboard up front so the menu item always opens something, even
        // before the first dictation.
        RunLog.regenerate()

        // Parakeet's models take ~20s to load from disk, and that cost lands on whichever
        // dictation touches them first — so the first hold after every launch would stall
        // with the HUD showing nothing. Warm them in the background instead, but only when
        // they're actually going to be used and are already downloaded.
        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        // Every `make install` relaunches the app and drops its windows. Restoring the
        // window when it was open last time keeps it from vanishing on each rebuild.
        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        Log.app.info("Blurt ready — hold \(Settings.shared.pushToTalkBinding.displayName) to dictate")
    }

    /// `blurt://clear` and `blurt://show`, used by the legacy HTML dashboard and
    /// as a scriptable way to raise the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "blurt" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
                Self.showComparisonWindow()
            default:
                break
            }
        }
    }

    /// Raises the comparison window without needing SwiftUI's `openWindow` environment
    /// value — usable from the app delegate and from a URL handler.
    static func showComparisonWindow() {
        RunStore.shared.reload()
        if let existing = NSApp.windows.first(where: { $0.title == "Engine comparison" }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = NSApp.windows.contains { $0.title == "Engine comparison" && $0.isVisible }
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
    }

    /// Shows and hides the HUD in step with the controller's state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    /// Arms the event tap the moment Accessibility lands.
    ///
    /// Watches `PermissionMonitor` rather than running its own `while !hasAccessibility`
    /// loop, so there is exactly one poller in the process and the UI sees the same state
    /// this does. `withObservationTracking` is one-shot, hence the re-arm.
    private func armHotkeyWhenPermitted() {
        let monitor = PermissionMonitor.shared
        withObservationTracking {
            _ = monitor.accessibility
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if monitor.accessibility {
                    self.controller.activate()
                    Log.app.info("Accessibility granted — hotkey armed")
                } else {
                    self.armHotkeyWhenPermitted()
                }
            }
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    let updates: UpdateController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded
    @State private var permissions = PermissionMonitor.shared

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Loading Parakeet models…" }
        // Reflects what's actually on disk, not just what this menu instance has done.
        return parakeetOnDisk ? "Parakeet models installed ✓" : "Download Parakeet models…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isDownloaded
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        Text("Hold \(settings.pushToTalkBinding.displayName) to dictate")

        Divider()

        // No Picker here any more: a binding can be any key or mouse button, which is not
        // an enumerable list. Settings owns the capture UI; this just reports and links.
        Button("Change push-to-talk key…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        Toggle("Compare mode (both engines)", isOn: $settings.compareMode)

        if !settings.compareMode {
            Picker("Engine", selection: $settings.engine) {
                ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
            if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
            // Tone only means anything through the model — the rule pass cannot rewrite.
            if settings.smartCleanup, FoundationModelFormatter.isAvailable {
                Picker("Tone", selection: $settings.toneMode) {
                    ForEach(ToneMode.allCases, id: \.self) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Divider()

        Button("Show comparison window") {
            RunStore.shared.reload()
            openWindow(id: "comparison")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("d")

        // Downloading ~470 MB on the first hold would look like a hang, so offer to do it
        // deliberately instead.
        if settings.engine == .parakeet {
            Button(parakeetStatus) { preloadParakeet() }
                .disabled(isPreloadingParakeet || parakeetOnDisk)
        }

        if !permissions.accessibility {
            Button("Grant Accessibility…") {
                Permissions.promptForAccessibility()
                Permissions.openAccessibilitySettings()
            }
        }
        if !permissions.microphone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        // The only place permissions can be reported truthfully: the running app is
        // attributed to itself, where a terminal-launched copy is attributed to the terminal.
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheck)

        Button("Copy Diagnostics") { Diagnostics.copyToPasteboard() }

        Button("Run Setup Again…") {
            OnboardingModel.restart()
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit Blurt") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
