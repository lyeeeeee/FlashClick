import ApplicationServices
import Cocoa

class AppController {
    static let shared = AppController()

    var window: OverlayWindow?
    var collectedElements: [UIElement] = []
    var inputBuffer = ""

    // 监听器引用
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?

    // 初始化时设置监听
    init() {
        setupObservers()
    }

    func setupObservers() {
        // 1. 监听 App 切换
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 获取当前激活的 App
            guard let userInfo = notification.userInfo,
                let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }

            // 【关键修改】如果激活的是我自己 (PID 相同)，什么都不做
            if app.processIdentifier == getpid() {
                print("👀 激活了 FlashClick (我自己)，忽略")
                return
            }

            print("🔄 切换到了其他 App: \(app.localizedName ?? "")，隐藏窗口")
            self?.hideWindow()
        }

        // 2. 监听全局鼠标点击
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            self?.hideWindow()
        }

        // 3. 监听本地鼠标点击
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            self?.hideWindow()
            return event
        }
    }

    func start() {
        print("🚀 正在扫描...")

        // 1. 调用 Scanner 获取数据
        collectedElements = UIScanner.scanCurrentWindow()

        if collectedElements.isEmpty {
            print("⚠️ 未找到元素")
            NSSound.beep()
            return
        }

        // 2. 根据距离中心点排序 (优化体验)
        if let screenFrame = NSScreen.main?.frame {
            let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
            collectedElements.sort { (node1, node2) -> Bool in
                let dist1 = hypot(node1.frame.midX - center.x, node1.frame.midY - center.y)
                let dist2 = hypot(node2.frame.midX - center.x, node2.frame.midY - center.y)
                return dist1 < dist2
            }
        }

        // 3. 分配标签 (使用 Homerow Key 算法)
        for i in 0..<collectedElements.count {
            collectedElements[i].id = AXHelpers.generateLabel(index: i)
        }

        // 4. 显示窗口
        showWindow()
    }

    func showWindow() {
        let screenRect = NSScreen.main!.frame
        if window == nil {
            window = OverlayWindow(
                contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
            window?.backgroundColor = NSColor.clear
            window?.isOpaque = false
            window?.hasShadow = false
            window?.level = .floating
        }

        // 每次显示时，重新创建一个 View 并把数据传进去
        let overlay = OverlayView(frame: screenRect)
        overlay.elements = self.collectedElements
        window?.contentView = overlay

        inputBuffer = ""
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // --- 这里就是你报错缺失的方法 ---
    func hideWindow() {
        window?.orderOut(nil)
        NSApplication.shared.hide(nil)
        inputBuffer = ""  // 重置输入缓存
    }

    func handleInput(_ char: String) {
        inputBuffer += char.uppercased()

        if let match = collectedElements.first(where: { $0.id == inputBuffer }) {
            // 点击逻辑
            let error = AXUIElementPerformAction(match.rawElement, kAXPressAction as CFString)
            if error != .success {
                // 模拟鼠标点击
                let centerX = match.frame.origin.x + match.frame.width / 2
                let centerY = match.frame.origin.y + match.frame.height / 2
                let point = CGPoint(x: centerX, y: centerY)
                let eventDown = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point,
                    mouseButton: .left)
                let eventUp = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point,
                    mouseButton: .left)
                eventDown?.post(tap: .cghidEventTap)
                usleep(10000)
                eventUp?.post(tap: .cghidEventTap)
            }
            hideWindow()
        } else {
            // 检查前缀
            let hasPotential = collectedElements.contains { $0.id.hasPrefix(inputBuffer) }
            if !hasPotential {
                inputBuffer = ""
                NSSound.beep()
            }
        }
        // 触发重绘 (如果做了高亮逻辑的话)
        window?.contentView?.needsDisplay = true
    }
}
