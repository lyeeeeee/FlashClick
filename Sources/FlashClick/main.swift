import Cocoa

class SingleInstanceLock {
    //private static var fileDescriptor: Int32 = -1
    static func tryLock() -> Bool {
        let lockFilePath: String = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "com.flashclick.app.lock")
        let fileDescriptor = open(lockFilePath, O_CREAT | O_RDWR, 0o666)
        if open(lockFilePath, O_CREAT | O_RDWR, 0o666) == -1 {
            FileLogger.shared.log("❌ 无法打开锁文件1: \(lockFilePath)")
            return false
        }
        // LOCK_EX: 排他锁 (Exclusive Lock)，只允许一个进程持有
        // LOCK_NB: 非阻塞 (Non-Blocking)，如果被锁了立刻返回失败，而不是死等
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return true
        } else {
            close(fileDescriptor)
            FileLogger.shared.log("❌ 无法打开锁文件3: \(lockFilePath)")
            return false
        }
    }
}

if !SingleInstanceLock.tryLock() {
    exit(0)
}

// 1. 设置为后台应用
let app: NSApplication = NSApplication.shared
app.setActivationPolicy(.accessory)

// 2. 注册热键
// 注意：这里需要保持 hotkey 变量的生命周期，不能让它释放
var hotkeys: [GlobalHotKey] = []

// Cmd + Shift + Space: 激活
hotkeys.append(
    GlobalHotKey(keyCode: 49) {
        if let frontApp: NSRunningApplication = NSWorkspace.shared.frontmostApplication {
            FileLogger.shared.log(
                "🔥 热键触发！当前目标 App: \(frontApp.localizedName ?? "Unknown") (PID: \(frontApp.processIdentifier))"
            )
        }
        AppController.shared.start()
    })

// Cmd + Shift + J: 向下滚动
hotkeys.append(
    GlobalHotKey(keyCode: 38) {
        AppController.shared.scroll(direction: .down, keyCode: 38)
    })

// Cmd + Shift + K: 向上滚动
hotkeys.append(
    GlobalHotKey(keyCode: 40) {
        AppController.shared.scroll(direction: .up, keyCode: 40)
    })

FileLogger.shared.log("👻 FlashClick 已启动 (后台模式)")
FileLogger.shared.log("⌨️ 请按 Cmd + Shift + Space 激活")
FileLogger.shared.log("⌨️ Cmd + Shift + J/K 滚动")

// 3. 启动
app.run()
