import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut via Carbon's `RegisterEventHotKey`.
///
/// Used for ⌃⌥V (paste last dictation). Carbon hot keys are delivered by the window server
/// to the registering app, need no Accessibility grant, and keep working when the event tap
/// can't be created — which is exactly when a fallback is most useful.
@MainActor
final class GlobalShortcut {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// Handlers by hot-key ID. The Carbon callback is a C function and can't capture context.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?
    private static var nextID: UInt32 = 1

    /// 'MRMR'
    nonisolated private static let signature: OSType = 0x4D52_4D52

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    var isRegistered: Bool { hotKeyRef != nil }

    /// Registers `keyCode` + Carbon `modifiers` (e.g. `controlKey | optionKey`), replacing any
    /// previous registration. Returns `false` if another app already owns the combination.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        unregister()
        guard Self.installHandlerIfNeeded() else { return false }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            Log.hotkey.error("RegisterEventHotKey failed: \(status)")
            return false
        }
        hotKeyRef = ref
        Self.handlers[id] = action
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalShortcut.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                // Plain integer out of the C callback; the handler runs on the main actor.
                let id = hotKeyID.id
                Task { @MainActor in GlobalShortcut.handlers[id]?() }
                return noErr
            },
            1,
            &spec,
            nil,
            &ref
        )
        guard status == noErr, let ref else {
            Log.hotkey.error("InstallEventHandler failed: \(status)")
            return false
        }
        eventHandler = ref
        return true
    }
}
