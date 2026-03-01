import Carbon
import Cocoa

class GlobalHotKey {
    var eventHandler: EventHandlerRef?
    var hotKeyRef: EventHotKeyRef?
    let callback: () -> Void
    let keyCode: Int
    let modifiers: Int

    var hotKeyID: EventHotKeyID?

    init(keyCode: Int, modifiers: Int = cmdKey + shiftKey, callback: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.callback = callback
        register()
    }

    func register() {
        let hotKeyID = EventHotKeyID(signature: OSType(keyCode), id: UInt32(keyCode))
        self.hotKeyID = hotKeyID

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                let holder = Unmanaged<GlobalHotKey>.fromOpaque(userData!).takeUnretainedValue()

                guard let event = event else { return OSStatus(eventNotHandledErr) }

                // Get the HotKeyID from the event
                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )

                // Check if it matches our registered ID
                if status == noErr,
                    eventHotKeyID.signature == holder.hotKeyID?.signature,
                    eventHotKeyID.id == holder.hotKeyID?.id
                {
                    holder.callback()
                    return noErr
                }

                return OSStatus(eventNotHandledErr)
            }, 1, &eventType, ptr, &eventHandler)

        // Register with dynamic key code and modifiers
        RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        FileLogger.shared.log("✅ 全局热键已注册: KeyCode \(keyCode)")
    }
}
