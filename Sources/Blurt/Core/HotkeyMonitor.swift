import BlurtInput
import CoreGraphics
import Foundation

/// Watches for a held key, modifier or mouse button using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
///
/// The event mask is built from the current binding rather than fixed, and that is a
/// privacy decision as much as a technical one: a session tap that asks for `keyDown` can
/// observe every character typed anywhere on the machine. Blurt has no business holding
/// that reach while it is waiting on a modifier or a mouse button, so it doesn't ask for it
/// — `reload(binding:)` tears the tap down and builds a narrower or wider one to match.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    var binding: PushToTalkBinding = .default
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        var mask: CGEventMask = 0
        for type in binding.requiredEventTypes {
            mask |= (1 << CGEventMask(type))
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let observed = ObservedEvent(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                    flags: event.flags.rawValue,
                    button: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
                    isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                )
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, event: observed)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.binding.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        // A binding change while the key is held would otherwise leave this stuck true and
        // swallow the next press.
        isPressed = false
    }

    /// Rebinds and rebuilds the tap, since the event mask depends on the binding.
    @discardableResult
    func reload(binding: PushToTalkBinding) -> Bool {
        self.binding = binding
        return start()
    }

    // MARK: - Tap callback

    /// The fields we need, copied out of the non-Sendable `CGEvent`.
    private struct ObservedEvent {
        let keyCode: Int64
        let flags: UInt64
        let button: Int
        let isAutorepeat: Bool
    }

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, event: ObservedEvent) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        switch binding {
        case .modifier(let modifier):
            guard type == .flagsChanged, event.keyCode == modifier.keyCode else { return false }
            return transition(to: event.flags & modifier.deviceFlag != 0)

        case .key(let code):
            guard event.keyCode == code else { return false }
            switch type {
            case .keyDown:
                // Holding a key produces a stream of repeats. Without this the press fires
                // over and over — but the repeat still has to be swallowed, or the character
                // lands in the document anyway.
                if event.isAutorepeat { return binding.consumesEvent }
                return transition(to: true)
            case .keyUp:
                return transition(to: false)
            default:
                return false
            }

        case .mouse(let button):
            guard event.button == button else { return false }
            switch type {
            case .otherMouseDown: return transition(to: true)
            case .otherMouseUp: return transition(to: false)
            default: return false
            }
        }
    }

    /// Fires press/release on an actual edge, and reports whether to swallow the event.
    ///
    /// The swallow decision is returned for *both* edges deliberately. Consuming the press
    /// while letting the release through leaves the target app believing the key is still
    /// held down — the failure the Windows port documents, and the reason this returns the
    /// same answer either way rather than only suppressing the press.
    private func transition(to pressed: Bool) -> Bool {
        guard pressed != isPressed else { return binding.consumesEvent }
        isPressed = pressed
        if pressed { onPress?() } else { onRelease?() }
        return binding.consumesEvent
    }
}
