import Cocoa

// 1. 设置为后台应用
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 2. 注册热键
// 注意：这里需要保持 hotkey 变量的生命周期，不能让它释放
let hotkey = GlobalHotKey {
    print("🔥 热键触发！")
    AppController.shared.start()
}

print("👻 FlashClick 已启动 (后台模式)")
print("⌨️ 请按 Cmd + Shift + Space 激活")

// 3. 启动
app.run()
