import Cocoa
import Carbon

class GlobalHotKey {
    var eventHandler: EventHandlerRef?
    var hotKeyRef: EventHotKeyRef?
    let callback: () -> Void
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        register()
    }
    
    func register() {
        let hotKeyID = EventHotKeyID(signature: 1, id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            let holder = Unmanaged<GlobalHotKey>.fromOpaque(userData!).takeUnretainedValue()
            holder.callback()
            return noErr
        }, 1, &eventType, ptr, &eventHandler)
        
        // Cmd + Shift + Space
        RegisterEventHotKey(49, UInt32(cmdKey + shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        print("✅ 全局热键已注册: Cmd + Shift + Space")
    }
}
