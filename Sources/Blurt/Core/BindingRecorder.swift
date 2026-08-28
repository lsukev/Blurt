import BlurtInput
import CoreGraphics
import Foundation
import Observation

/// Captures the next key, modifier or mouse button the user presses, to bind it.
///
/// A separate, short-lived tap rather than a mode on `HotkeyMonitor`. While recording it
/// asks for everything — `flagsChanged`, `keyDown`, `otherMouseDown` — which is a far wider
/// reach than the monitor normally holds, so it lives on its own, runs only while a capture
/// panel is open, and tears itself down the moment it has an answer. `HotkeyMonitor` keeps
/// its narrow, binding-derived mask untouched.
///
/// Every captured event is swallowed. Otherwise pressing Space to bind it also types a
/// space into whatever is behind the panel.
@MainActor
@Observable
final class BindingRecorder {
    private(set) var isRecording = false

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var onCapture: ((PushToTalkBinding) -> Void)?
    @ObservationIgnored private var priorFlags: UInt64 = 0

    /// - Returns: `false` if the tap couldn't be created — missing Accessibility permission.
    @discardableResult
    func start(onCapture: @escaping (PushToTalkBinding) -> Void) -> Bool {
        cancel()
        self.onCapture = onCapture

        let mask: CGEventMask =
            (1 << CGEventMask(CGEventType.flagsChanged.rawValue))
            | (1 << CGEventMask(CGEventType.keyDown.rawValue))
            | (1 << CGEventMask(CGEventType.otherMouseDown.rawValue))

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let recorder = Unmanaged<BindingRecorder>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags.rawValue
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

                // The tap is on the main run loop, so this callback genuinely runs on the
                // main thread.
                let consume = MainActor.assumeIsolated {
                    recorder.capture(type: type, keyCode: keyCode, flags: flags,
                                     button: button, isRepeat: isRepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("binding capture tap failed — Accessibility permission missing?")
            self.onCapture = nil
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        priorFlags = CGEventSource.flagsState(.combinedSessionState).rawValue
        isRecording = true
        return true
    }

    func cancel() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        onCapture = nil
        isRecording = false
    }

    private func capture(
        type: CGEventType,
        keyCode: Int64,
        flags: UInt64,
        button: Int,
        isRepeat: Bool
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let captured: PushToTalkBinding?
        switch type {
        case .flagsChanged:
            // Only on the way *down*. A modifier released while the panel opens would
            // otherwise be captured as if the user had chosen it.
            guard let modifier = PushToTalkBinding.Modifier.named(keyCode: keyCode),
                  flags & modifier.deviceFlag != 0,
                  priorFlags & modifier.deviceFlag == 0
            else {
                priorFlags = flags
                return false
            }
            captured = .modifier(modifier)

        case .keyDown:
            guard !isRepeat else { return true }
            captured = .key(code: keyCode)

        case .otherMouseDown:
            // Returns nil for buttons 0 and 1, so left and right click simply never bind.
            captured = PushToTalkBinding.mouseButton(button)

        default:
            captured = nil
        }

        priorFlags = flags
        guard let captured else { return false }

        let handler = onCapture
        cancel()
        handler?(captured)
        Log.hotkey.info("captured binding \(captured.displayName, privacy: .public)")
        return true
    }
}
