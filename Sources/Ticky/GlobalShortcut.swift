import AppKit
import Carbon.HIToolbox

/// System-wide shortcut that opens the menu bar panel (#6), ⌃⌥T unless the user records another (#110).
/// Carbon hot keys need no accessibility permission.
@MainActor enum GlobalShortcut {
    static let defaultKey = (code: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), key: "T")

    static var keyCode: UInt32 { (UserDefaults.standard.object(forKey: "shortcutKeyCode") as? Int).map(UInt32.init) ?? defaultKey.code }
    static var modifiers: UInt32 { (UserDefaults.standard.object(forKey: "shortcutModifiers") as? Int).map(UInt32.init) ?? defaultKey.modifiers }
    static var label: String { label(modifiers: modifiers, key: UserDefaults.standard.string(forKey: "shortcutKey") ?? defaultKey.key) }

    static func label(modifiers: UInt32, key: String) -> String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// Carbon modifier mask for a recorded key; nil without ⌘, ⌃ or ⌥, because such a shortcut would swallow normal typing.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32? {
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        var mask = 0
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.shift) { mask |= shiftKey }
        if flags.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    static func save(keyCode: UInt16, modifiers: UInt32, key: String) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "shortcutKeyCode")
        defaults.set(Int(modifiers), forKey: "shortcutModifiers")
        defaults.set(key, forKey: "shortcutKey")
        setEnabled(defaults.object(forKey: "globalShortcut") as? Bool ?? true)
    }

    static func reset() {
        ["shortcutKeyCode", "shortcutModifiers", "shortcutKey"].forEach(UserDefaults.standard.removeObject)
        setEnabled(UserDefaults.standard.object(forKey: "globalShortcut") as? Bool ?? true)
    }
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func setEnabled(_ enabled: Bool) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard enabled else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalShortcut.openPanel() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x544F_444F), id: 1) // "TODO"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    /// MenuBarExtra has no API to open its window, so the shortcut clicks the app's status item.
    static func openPanel() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.className.contains("StatusBarWindow") {
            if let button = statusButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(statusButton).first
    }
}

/// Optional Dock icon (#86): the app is a menu bar app (LSUIElement) and only shows up in the Dock when wanted.
@MainActor enum DockIcon {
    static func setVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
