//  GlobalHotKey.swift
//  Astrid for Mac — system-wide hotkey (M0 de-risk artifact)
//
//  This is the crux of the M0 spike: prove a system-wide hotkey works in an App Store
//  *sandboxed* build. `RegisterEventHotKey` (Carbon) registers a single dedicated hotkey
//  and does NOT require the Accessibility permission (that's only needed to *monitor*
//  arbitrary global keystrokes, which we do not do). Validated on BOTH the sandboxed
//  App Store build and the direct build — see docs/archive/MAC_M0_NOTES.md §"Hotkey de-risk".
//
//  The Carbon calls sit behind `HotKeyRegistrar` so the registration rules — one registration per
//  key, a failure leaves nothing behind, release on deinit — are testable without Carbon (AITD-540).

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// Where a hot key is actually registered. `CarbonHotKeyRegistrar` in the app; a recording fake in
/// tests.
protocol HotKeyRegistrar: AnyObject {
    /// The handle to release later, or nil when the system refused the key.
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, onPress: @escaping () -> Void) -> AnyObject?
    func unregister(_ handle: AnyObject, id: UInt32)
}

public final class GlobalHotKey {
    public static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    private let handle: AnyObject
    private let id: UInt32
    private let registrar: HotKeyRegistrar
    private static var nextID: UInt32 = 1

    public convenience init?(keyCode: UInt32 = optionSpace.keyCode,
                             modifiers: UInt32 = optionSpace.modifiers,
                             action: @escaping () -> Void) {
        self.init(keyCode: keyCode, modifiers: modifiers, registrar: CarbonHotKeyRegistrar.shared, action: action)
    }

    init?(keyCode: UInt32, modifiers: UInt32, registrar: HotKeyRegistrar, action: @escaping () -> Void) {
        let id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        guard let handle = registrar.register(keyCode: keyCode, modifiers: modifiers, id: id, onPress: action) else {
            return nil
        }
        self.id = id
        self.handle = handle
        self.registrar = registrar
    }

    deinit {
        registrar.unregister(handle, id: id)
    }
}

/// The Carbon `RegisterEventHotKey` path: one application-wide event handler, installed once, that
/// dispatches each press to the action registered under its id.
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    static let shared = CarbonHotKeyRegistrar()

    private final class Ref { let value: EventHotKeyRef; init(_ value: EventHotKeyRef) { self.value = value } }
    private static var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerInstalled = false

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, onPress: @escaping () -> Void) -> AnyObject? {
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x41535444) /* 'ASTD' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        Self.handlers[id] = onPress
        return Ref(ref)
    }

    func unregister(_ handle: AnyObject, id: UInt32) {
        if let ref = handle as? Ref { UnregisterEventHotKey(ref.value) }
        Self.handlers[id] = nil
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            CarbonHotKeyRegistrar.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
#endif
