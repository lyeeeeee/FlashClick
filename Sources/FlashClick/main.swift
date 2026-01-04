import Cocoa

// 1. 设置为后台应用
let app: NSApplication = NSApplication.shared
app.setActivationPolicy(.accessory)

// 2. 注册热键
// 注意：这里需要保持 hotkey 变量的生命周期，不能让它释放
let hotkey = GlobalHotKey {
    if let frontApp: NSRunningApplication = NSWorkspace.shared.frontmostApplication {
        print(
            "🔥 热键触发！当前目标 App: \(frontApp.localizedName ?? "Unknown") (PID: \(frontApp.processIdentifier))"
        )
    }
    AppController.shared.start()
}

print("👻 FlashClick 已启动 (后台模式)")
print("⌨️ 请按 Cmd + Shift + Space 激活")

// 3. 启动
app.run()
