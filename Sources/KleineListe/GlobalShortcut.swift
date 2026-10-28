import AppKit
import Carbon.HIToolbox

/// System-wide ⌃⌥T that opens the menu bar panel (#6). Carbon hot keys need no accessibility permission.
@MainActor enum GlobalShortcut {
    static let label = "⌃⌥T"
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
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
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
