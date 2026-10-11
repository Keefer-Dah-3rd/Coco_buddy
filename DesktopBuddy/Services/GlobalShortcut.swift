import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut (⌃⌥C) that opens Coco from any app.
///
/// Uses the Carbon hot-key API, which macOS still supports for exactly this and which —
/// unlike monitoring all key presses — needs no Accessibility or Input Monitoring permission.
final class GlobalShortcut {
    static let displayName = "⌃⌥C"
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Returns false when the shortcut couldn't be claimed — usually because another app owns it.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled { return register() }
        unregister()
        return true
    }

    private func register() -> Bool {
        guard hotKey == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), Self.callback, 1, &type, context, &handler)
        let id = EventHotKeyID(signature: OSType(0x434F434F), id: 1)  // "COCO"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            unregister()
            return false
        }
        return true
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    /// Carbon delivers hot-key events on the main thread.
    private static let callback: EventHandlerUPP = { _, _, context in
        guard let context else { return noErr }
        let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { shortcut.onPress?() }
        return noErr
    }
}
