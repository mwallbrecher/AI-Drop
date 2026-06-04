import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey via Carbon `RegisterEventHotKey`.
///
/// Unlike an `NSEvent` global monitor this **consumes** the keystroke (so the combo
/// never leaks into the frontmost app) and needs **no Accessibility permission**.
/// Used for the ⌃⌘V clipboard-history picker. One key per instance.
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    /// Called on the main thread when the hotkey fires.
    fileprivate var onFire: (() -> Void)?

    // 'AIDR' — any non-zero signature; pairs with id to identify our hotkey.
    private let hotKeyID = EventHotKeyID(signature: 0x4149_4452, id: 1)

    /// Register `keyCode` (virtual key, e.g. `kVK_ANSI_V`) with Carbon modifier mask
    /// (`cmdKey` / `controlKey` / `optionKey` / `shiftKey`). Replaces any prior key.
    func register(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        unregister()
        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback,
                            1, &spec, selfPtr, &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let h = eventHandler { RemoveEventHandler(h); eventHandler = nil }
        onFire = nil
    }

    deinit { unregister() }
}

/// Free C callback (Carbon needs a bare function pointer, no captured context). The
/// instance arrives via `userData`. Carbon hotkey events are delivered on the main
/// runloop, so it's safe to assume main-actor isolation and call the stored closure.
private func hotkeyCallback(_ next: EventHandlerCallRef?,
                            _ event: EventRef?,
                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    MainActor.assumeIsolated {
        Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().onFire?()
    }
    return noErr
}
