import Foundation

/// What you hold to dictate.
///
/// Platform-neutral on purpose, like `BlurtDictionary` and `BlurtSetup`: the decisions here
/// — what a binding is called, whether its event must be swallowed, which event types the
/// tap needs to ask for, how it round-trips through `UserDefaults` — are worth testing, and
/// the `CGEventTap` that acts on them cannot be tested at all. Key codes are carried as
/// plain integers so this file needs no Carbon import.

public enum PushToTalkBinding: Sendable, Equatable, Hashable {
    /// A modifier key. Held without typing anything, which is why these were the only
    /// option originally.
    case modifier(Modifier)
    /// Any non-modifier key, by virtual key code.
    case key(code: Int64)
    /// A mouse button, numbered as Core Graphics numbers them.
    ///
    /// Only button 2 and up are representable here, and that is enforced at construction.
    /// Buttons 0 and 1 are left and right click; binding either would make the machine
    /// effectively unusable, and the tap only ever asks for `otherMouse` events, so they
    /// are excluded by construction rather than by a check someone can forget.
    case mouse(button: Int)

    public static let lowestBindableMouseButton = 2

    /// Returns nil for left (0) and right (1) click.
    public static func mouseButton(_ number: Int) -> PushToTalkBinding? {
        guard number >= lowestBindableMouseButton else { return nil }
        return .mouse(button: number)
    }

    public static let `default` = PushToTalkBinding.modifier(.rightOption)

    // MARK: - Modifiers

    public enum Modifier: String, CaseIterable, Sendable, Equatable, Hashable {
        case leftControl, rightControl
        case leftShift, rightShift
        case leftOption, rightOption
        case leftCommand, rightCommand
        case fn

        public var keyCode: Int64 {
            switch self {
            case .leftControl: 59
            case .rightControl: 62
            case .leftShift: 56
            case .rightShift: 60
            case .leftOption: 58
            case .rightOption: 61   // kVK_RightOption
            case .leftCommand: 55
            case .rightCommand: 54  // kVK_RightCommand
            case .fn: 63            // kVK_Function
            }
        }

        /// The device-*dependent* mask for this specific physical key.
        ///
        /// The public `CGEventFlags` constants are union masks — `maskAlternate` is set
        /// whenever *either* Option key is down. Using one means: hold Left ⌥, tap Right ⌥,
        /// and the release is invisible, because the union bit is still set by the left key.
        /// The mic stays open and the next press is swallowed too. These raw values are the
        /// NX_DEVICE* masks from IOKit, which keep the left/right distinction.
        public var deviceFlag: UInt64 {
            switch self {
            case .leftControl: 0x0001    // NX_DEVICELCTLKEYMASK
            case .leftShift: 0x0002      // NX_DEVICELSHIFTKEYMASK
            case .rightShift: 0x0004     // NX_DEVICERSHIFTKEYMASK
            case .leftCommand: 0x0008    // NX_DEVICELCMDKEYMASK
            case .rightCommand: 0x0010   // NX_DEVICERCMDKEYMASK
            case .leftOption: 0x0020     // NX_DEVICELALTKEYMASK
            case .rightOption: 0x0040    // NX_DEVICERALTKEYMASK
            case .rightControl: 0x2000   // NX_DEVICERCTLKEYMASK
            case .fn: 0x800000           // NX_SECONDARYFNMASK — no left/right variant exists
            }
        }

        /// Looks a modifier up from the key code the tap reported, for binding capture.
        public static func named(keyCode: Int64) -> Modifier? {
            allCases.first { $0.keyCode == keyCode }
        }

        public var displayName: String {
            switch self {
            case .leftControl: "Left ⌃"
            case .rightControl: "Right ⌃"
            case .leftShift: "Left ⇧"
            case .rightShift: "Right ⇧"
            case .leftOption: "Left ⌥"
            case .rightOption: "Right ⌥"
            case .leftCommand: "Left ⌘"
            case .rightCommand: "Right ⌘"
            case .fn: "fn"
            }
        }
    }

    // MARK: - Naming

    public var displayName: String {
        switch self {
        case .modifier(let modifier): modifier.displayName
        case .key(let code): Self.keyName(for: code)
        case .mouse(let button): "Mouse button \(button + 1)"
        }
    }

    // MARK: - Suppression

    /// Whether the event must be swallowed rather than passed along.
    ///
    /// This is the rule that decides between "hold a key to dictate" and "hold a key to type
    /// forty of that character into your document".
    public var consumesEvent: Bool {
        switch self {
        case .modifier(.fn):
            // Swallowing fn breaks fn+arrow, fn+delete and the emoji picker. It's also
            // harmless not to: fn types nothing on its own.
            false
        case .modifier:
            true
        case .key:
            // Mandatory. A plain key that isn't swallowed types its character while you
            // dictate. Both down *and* up must be swallowed — swallow the down and let the
            // up escape and the target app believes the key is still held.
            true
        case .mouse:
            true
        }
    }

    /// Whether binding this would take something away from the user, and what.
    ///
    /// Returned rather than blocked: the ask was "any key", and refusing to honour that is
    /// narrower than what was wanted. But a plain key is swallowed system-wide while Blurt
    /// runs, so the consequence is named at the moment of choosing rather than discovered
    /// later with a keyboard that no longer types spaces.
    public var warning: String? {
        switch self {
        case .mouse:
            nil
        case .modifier(let modifier):
            // Shift and Control are chord partners far more than they are keys in their own
            // right, and this binding swallows them. Option and Command on the right-hand
            // side are the ones nothing else reaches for, which is why one is the default.
            switch modifier {
            case .leftShift, .rightShift, .leftControl, .rightControl:
                "\(modifier.displayName) is often held as part of a shortcut. Blurt will "
                    + "swallow it, so those shortcuts stop working while it runs."
            default:
                nil
            }
        case .key(let code):
            if Self.functionKeyCodes.contains(code) {
                // F13–F20 send nothing and mean nothing to the system. The sweet spot.
                nil
            } else if let name = Self.criticalKeyNames[code] {
                "\(name) is used constantly by macOS. While Blurt runs you will not be able "
                    + "to use it for anything else."
            } else {
                "You will not be able to type \(Self.keyName(for: code)) anywhere while "
                    + "Blurt is running."
            }
        }
    }

    /// Keys that would make the machine genuinely hard to use, for a stronger warning.
    private static let criticalKeyNames: [Int64: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete",
    ]

    /// F13–F20. Nothing types them and macOS assigns them nothing by default.
    public static let functionKeyCodes: Set<Int64> = [105, 107, 113, 106, 64, 79, 80, 90]

    // MARK: - Persistence
    //
    // Stored as a short tagged string rather than JSON so the value stays legible in
    // `defaults read` and in a bug report.

    public var storageValue: String {
        switch self {
        case .modifier(let m): "modifier:\(m.rawValue)"
        case .key(let code): "key:\(code)"
        case .mouse(let button): "mouse:\(button)"
        }
    }

    /// Parses a stored value, including the three bare strings written by versions before
    /// bindings existed. Without that migration every existing install silently resets to
    /// the default on upgrade.
    public init?(storageValue raw: String) {
        if let legacy = Modifier(rawValue: raw) {
            self = .modifier(legacy)
            return
        }
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let value = String(parts[1])

        switch parts[0] {
        case "modifier":
            guard let m = Modifier(rawValue: value) else { return nil }
            self = .modifier(m)
        case "key":
            guard let code = Int64(value) else { return nil }
            self = .key(code: code)
        case "mouse":
            guard let button = Int(value), let binding = Self.mouseButton(button) else { return nil }
            self = binding
        default:
            return nil
        }
    }

    // MARK: - Key names

    /// Names for the keys worth naming. Anything else falls back to its code, which is ugly
    /// but honest — inventing a label for an unknown key code would be worse.
    private static let keyNames: [Int64: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
    ]

    public static func keyName(for code: Int64) -> String {
        keyNames[code] ?? "Key \(code)"
    }

    // MARK: - Tap scope

    /// Which Core Graphics event types the tap must ask for.
    ///
    /// Deliberately derived from the binding rather than fixed. A session tap that requests
    /// `keyDown` observes every character typed anywhere on the machine — a reach this app
    /// has no business holding when it is watching for a modifier or a mouse button. So the
    /// mask narrows to whatever the current binding actually needs, and rebinding rebuilds
    /// the tap. Raw values match `CGEventType`.
    public var requiredEventTypes: Set<UInt32> {
        switch self {
        case .modifier:
            [12]           // flagsChanged
        case .key:
            [10, 11]       // keyDown, keyUp
        case .mouse:
            [25, 26]       // otherMouseDown, otherMouseUp
        }
    }
}
