import Foundation
import Carbon.HIToolbox

final class HotKeyManager {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    private var startRef: EventHotKeyRef?
    private var stopRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private enum HotKeyID: UInt32 { case start = 1, stop = 2 }

    func registerDefaults() {
        // ⌘⌥S to start, ⌘⌥X to stop
        registerHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: cmdKey | optionKey, id: .start)
        registerHotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: cmdKey | optionKey, id: .stop)
    }

    deinit {
        unregisterAll()
    }

    func unregisterAll() {
        if let r = startRef { UnregisterEventHotKey(r) }
        if let r = stopRef { UnregisterEventHotKey(r) }
        startRef = nil
        stopRef = nil
        if let h = handlerRef { RemoveEventHandler(h) }
        handlerRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { (next, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if status == noErr {
                switch HotKeyID(rawValue: hkID.id) {
                case .start: manager.onStart?()
                case .stop: manager.onStop?()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }

    private func registerHotKey(keyCode: UInt32, modifiers: Int, id: HotKeyID) {
        installHandlerIfNeeded()
        var hotKeyID = EventHotKeyID(signature: OSType(0x41434B52), id: id.rawValue) // 'ACKR'
        let mods = UInt32(modifiers)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        switch id {
        case .start: startRef = ref
        case .stop:  stopRef = ref
        }
    }
}
