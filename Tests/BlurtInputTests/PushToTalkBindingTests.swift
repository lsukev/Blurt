import Testing

@testable import BlurtInput

@Suite("Push-to-talk bindings")
struct PushToTalkBindingTests {

    // MARK: - Migration

    @Test("the three pre-binding settings still resolve, so nobody's key resets on upgrade")
    func legacyValuesMigrate() {
        #expect(PushToTalkBinding(storageValue: "rightOption") == .modifier(.rightOption))
        #expect(PushToTalkBinding(storageValue: "fn") == .modifier(.fn))
        #expect(PushToTalkBinding(storageValue: "rightCommand") == .modifier(.rightCommand))
    }

    @Test("every binding round-trips through its stored form")
    func storageRoundTrips() {
        let cases: [PushToTalkBinding] = [
            .modifier(.rightOption), .modifier(.fn), .modifier(.rightCommand),
            .key(code: 105), .key(code: 49), .mouse(button: 3), .mouse(button: 2),
        ]
        for binding in cases {
            #expect(PushToTalkBinding(storageValue: binding.storageValue) == binding)
        }
    }

    @Test("junk in defaults is rejected rather than guessed at")
    func rejectsMalformedStorage() {
        for junk in ["", "key", "key:", "key:abc", "mouse:one", "wat:1", ":", "modifier:nope"] {
            #expect(PushToTalkBinding(storageValue: junk) == nil, "\"\(junk)\" should not parse")
        }
    }

    // MARK: - Mouse safety

    @Test("left and right click cannot be constructed")
    func leftAndRightClickAreUnrepresentable() {
        #expect(PushToTalkBinding.mouseButton(0) == nil, "left click must not be bindable")
        #expect(PushToTalkBinding.mouseButton(1) == nil, "right click must not be bindable")
        #expect(PushToTalkBinding.mouseButton(2) != nil)
        #expect(PushToTalkBinding.mouseButton(3) != nil)
    }

    @Test("a stored left-click binding is refused on read too")
    func storedLeftClickIsRefused() {
        #expect(PushToTalkBinding(storageValue: "mouse:0") == nil)
        #expect(PushToTalkBinding(storageValue: "mouse:1") == nil)
        #expect(PushToTalkBinding(storageValue: "mouse:2") == .mouse(button: 2))
    }

    // MARK: - Suppression

    @Test("a plain key is always swallowed, or it types while you dictate")
    func plainKeysAreConsumed() {
        #expect(PushToTalkBinding.key(code: 105).consumesEvent)
        #expect(PushToTalkBinding.key(code: 12).consumesEvent)
    }

    @Test("fn is never swallowed — it would break fn+arrow and the emoji picker")
    func fnIsNotConsumed() {
        #expect(!PushToTalkBinding.modifier(.fn).consumesEvent)
        #expect(PushToTalkBinding.modifier(.rightOption).consumesEvent)
        #expect(PushToTalkBinding.modifier(.rightCommand).consumesEvent)
    }

    // MARK: - Warnings

    @Test("modifiers and mouse buttons cost the user nothing, so they carry no warning")
    func safeBindingsHaveNoWarning() {
        #expect(PushToTalkBinding.modifier(.rightOption).warning == nil)
        #expect(PushToTalkBinding.modifier(.fn).warning == nil)
        #expect(PushToTalkBinding.mouse(button: 3).warning == nil)
    }

    @Test("F13–F20 type nothing, so they are the one safe key class")
    func functionKeysHaveNoWarning() {
        for code in PushToTalkBinding.functionKeyCodes {
            #expect(PushToTalkBinding.key(code: code).warning == nil,
                    "\(PushToTalkBinding.keyName(for: code)) should be warning-free")
        }
    }

    @Test("an ordinary letter warns that you lose it system-wide")
    func letterKeysWarn() {
        let warning = PushToTalkBinding.key(code: 12).warning  // Q
        #expect(warning != nil)
        #expect(warning?.contains("Q") == true)
    }

    @Test("keys macOS depends on get the stronger warning")
    func criticalKeysWarnHarder() {
        for (code, name) in [(Int64(49), "Space"), (Int64(36), "Return"), (Int64(53), "Escape")] {
            let warning = PushToTalkBinding.key(code: code).warning
            #expect(warning?.contains(name) == true, "\(name) should be named in its warning")
            #expect(warning?.contains("macOS") == true, "\(name) should get the stronger wording")
        }
    }

    // MARK: - Tap scope

    @Test("the tap only asks for keyDown when a plain key is actually bound")
    func tapScopeFollowsTheBinding() {
        // keyDown (10) lets the tap observe every character typed on the machine. It must
        // not be requested for bindings that have no use for it.
        #expect(!PushToTalkBinding.modifier(.rightOption).requiredEventTypes.contains(10))
        #expect(!PushToTalkBinding.mouse(button: 3).requiredEventTypes.contains(10))
        #expect(PushToTalkBinding.key(code: 105).requiredEventTypes.contains(10))
    }

    @Test("each binding asks for both halves of its event pair")
    func tapScopeIsComplete() {
        // Missing the "up" half is how a swallowed key ends up stuck down forever.
        #expect(PushToTalkBinding.key(code: 105).requiredEventTypes == [10, 11])
        #expect(PushToTalkBinding.mouse(button: 3).requiredEventTypes == [25, 26])
        #expect(PushToTalkBinding.modifier(.rightOption).requiredEventTypes == [12])
    }

    // MARK: - Naming

    @Test("bindings name themselves in terms a user recognises")
    func displayNames() {
        #expect(PushToTalkBinding.modifier(.rightOption).displayName == "Right ⌥")
        #expect(PushToTalkBinding.key(code: 105).displayName == "F13")
        #expect(PushToTalkBinding.key(code: 49).displayName == "Space")
        // Mouse buttons are 0-indexed internally and 1-indexed to humans.
        #expect(PushToTalkBinding.mouse(button: 2).displayName == "Mouse button 3")
    }

    @Test("an unknown key code reports itself rather than inventing a name")
    func unknownKeyCodesAreHonest() {
        #expect(PushToTalkBinding.key(code: 999).displayName == "Key 999")
    }
}

@Suite("Modifier table")
struct ModifierTableTests {

    // Nine entries of hand-copied IOKit constants. A duplicated line compiles fine and
    // produces a binding that fires on the wrong physical key, so the table is checked
    // rather than trusted.

    @Test("every modifier has a distinct key code")
    func keyCodesAreUnique() {
        let codes = PushToTalkBinding.Modifier.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count, "duplicate key code in the modifier table")
    }

    @Test("every modifier has a distinct device flag")
    func deviceFlagsAreUnique() {
        let flags = PushToTalkBinding.Modifier.allCases.map(\.deviceFlag)
        #expect(Set(flags).count == flags.count, "duplicate device flag in the modifier table")
    }

    @Test("every device flag is a single bit")
    func deviceFlagsAreSingleBits() {
        // These are masks for one physical key. A value with two bits set would match a
        // second key as well, and the release of either would look like a release of ours.
        for modifier in PushToTalkBinding.Modifier.allCases {
            #expect(modifier.deviceFlag.nonzeroBitCount == 1,
                    "\(modifier.displayName) flag \(modifier.deviceFlag) is not a single bit")
        }
    }

    @Test("a modifier can be recovered from the key code the tap reports")
    func lookupByKeyCodeRoundTrips() {
        for modifier in PushToTalkBinding.Modifier.allCases {
            #expect(PushToTalkBinding.Modifier.named(keyCode: modifier.keyCode) == modifier)
        }
        #expect(PushToTalkBinding.Modifier.named(keyCode: 12) == nil, "Q is not a modifier")
    }

    @Test("every modifier names itself")
    func allHaveDistinctNames() {
        let names = PushToTalkBinding.Modifier.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(!names.contains { $0.isEmpty })
    }

    @Test("the original three keep the exact codes and flags they shipped with")
    func originalThreeAreUnchanged() {
        // These shipped in v0.1.0. Changing one silently rebinds every existing install.
        #expect(PushToTalkBinding.Modifier.rightOption.keyCode == 61)
        #expect(PushToTalkBinding.Modifier.rightOption.deviceFlag == 0x40)
        #expect(PushToTalkBinding.Modifier.rightCommand.keyCode == 54)
        #expect(PushToTalkBinding.Modifier.rightCommand.deviceFlag == 0x10)
        #expect(PushToTalkBinding.Modifier.fn.keyCode == 63)
    }
}
