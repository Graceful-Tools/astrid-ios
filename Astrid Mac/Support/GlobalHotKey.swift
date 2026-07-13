//  GlobalHotKey.swift
//  Astrid for Mac — system-wide hotkey (M0 de-risk artifact)
//
//  This is the crux of the M0 spike: prove a system-wide hotkey works in an App Store
//  *sandboxed* build. `RegisterEventHotKey` (Carbon) registers a single dedicated hotkey
//  and does NOT require the Accessibility permission (that's only needed to *monitor*
//  arbitrary global keystrokes, which we do not do). Validated on BOTH the sandboxed
//  App Store build and the direct build — see docs/MAC_M0_NOTES.md §"Hotkey de-risk".

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// Registers one global hotkey and invokes `action` when pressed, from anywhere in the OS.
/// Default binding: ⌥Space (Option+Space). Rebindable — pass keyCode/modifiers.
public final class GlobalHotKey {

    // Common values for convenience (Carbon virtual key codes + modifier masks).
    public static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    /// Returns nil if the OS refused to register the hotkey (e.g. already taken).
    public init?(keyCode: UInt32 = optionSpace.keyCode,
                 modifiers: UInt32 = optionSpace.modifiers,
                 action: @escaping () -> Void) {
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.handlers[id] = action
        GlobalHotKey.installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x41535444) /* 'ASTD' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            GlobalHotKey.handlers[id] = nil
            return nil
        }
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            GlobalHotKey.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        GlobalHotKey.handlers[id] = nil
    }
}
#endif
