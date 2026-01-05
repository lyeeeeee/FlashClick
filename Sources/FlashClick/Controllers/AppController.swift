import ApplicationServices
import Cocoa

class AppController {
    static let shared = AppController()

    var window: OverlayWindow?
    var collectedElements: [UIElement] = []
    var inputBuffer = ""

    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?

    var isContinuousMode = false
    var pendingRestartWorkItem: DispatchWorkItem?
    var ignoreNextClickEvent = false

    init() {
        setupObservers()
    }

    func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }

            if app.processIdentifier == getpid() { return }
            if self?.ignoreNextClickEvent == true { return }
            self?.hideWindow()
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            if self?.ignoreNextClickEvent == true { return }
            self?.hideWindow()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            if self?.ignoreNextClickEvent == true { return event }
            self?.hideWindow()
            return event
        }
    }

    func start() {
        collectedElements = UIScanner.scanCurrentWindow()

        if collectedElements.isEmpty {
            FileLogger.shared.log("⚠️ 未找到元素")
            NSSound.beep()
            return
        }

        // 排序
        if let screenFrame = NSScreen.main?.frame {
            let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
            collectedElements.sort { (node1, node2) -> Bool in
                let dist1 = hypot(node1.frame.midX - center.x, node1.frame.midY - center.y)
                let dist2 = hypot(node2.frame.midX - center.x, node2.frame.midY - center.y)
                return dist1 < dist2
            }
        }

        // 分配标签
        for i in 0..<collectedElements.count {
            collectedElements[i].id = AXHelpers.generateLabel(index: i)
        }

        // 显示窗口 (传入第一个元素的位置，用于定位屏幕)
        if let firstElement = collectedElements.first {
            showWindow(at: firstElement.frame)
        }
    }

    // 【修改点】增加 targetFrame 参数，用于定位屏幕
    func showWindow(at targetFrame: CGRect) {
        // 1. 找到包含目标元素的屏幕
        // 如果找不到，就默认用主屏幕
        let targetScreen =
            NSScreen.screens.first { screen in
                NSIntersectionRect(screen.frame, targetFrame) != .zero
            } ?? NSScreen.main ?? NSScreen.screens[0]

        let screenRect = targetScreen.frame

        if window == nil {
            window = OverlayWindow(
                contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
            window?.backgroundColor = NSColor.clear
            window?.isOpaque = false
            window?.hasShadow = false
            window?.level = .floating
        }

        // 2. 把窗口移动到目标屏幕
        window?.setFrame(screenRect, display: true)

        // 3. 传递数据并显示
        let overlay = OverlayView(frame: screenRect)
        overlay.elements = self.collectedElements
        window?.contentView = overlay

        inputBuffer = ""
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        suspendWindow()
    }

    func suspendWindow() {
        window?.orderOut(nil)
        NSApplication.shared.hide(nil)
        inputBuffer = ""
    }

    func toggleContinuousMode() {
        isContinuousMode.toggle()
        FileLogger.shared.log("🔄 连续模式: \(isContinuousMode ? "开启" : "关闭")")
        window?.contentView?.needsDisplay = true
    }

    func simulateMouseClick(at rect: CGRect, targetElement: UIElement? = nil) {
        let centerX = rect.origin.x + rect.width / 2
        let centerY = rect.origin.y + rect.height / 2
        let point = CGPoint(x: centerX, y: centerY)

        // Prevent monitors from cancelling the loop during simulated interaction
        ignoreNextClickEvent = true
        // Safety reset in case async blocks fail or timing is off
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ignoreNextClickEvent = false
        }

        FileLogger.shared.log("🖱️ 准备点击: (\(Int(centerX)), \(Int(centerY)))")

        // 1. 【关键步骤】尝试先激活目标 App
        // 如果我们知道目标元素属于哪个 App，就先激活它
        if let rawElement = targetElement?.rawElement {
            var pid: pid_t = 0
            AXUIElementGetPid(rawElement, &pid)
            if let app = NSRunningApplication(processIdentifier: pid) {
                // 强制激活 App，确保它能接收鼠标事件
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // 2. 稍微延时，等待 App 激活完成 (Arc/Chrome 需要这点时间)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {

            // 创建事件源 (有时候 nil 会被拦截，用 HIDSystemState 更好)
            let source = CGEventSource(stateID: .hidSystemState)

            guard
                let eventDown: CGEvent = CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point,
                    mouseButton: .left),
                let eventUp = CGEvent(
                    mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point,
                    mouseButton: .left)
            else {
                return
            }

            // 3. 发送点击
            eventDown.post(tap: .cghidEventTap)
            usleep(1000)  // 10ms
            eventUp.post(tap: .cghidEventTap)

            // 4. 【针对 Arc 的补丁】双击策略
            // 有些 Chromium 窗口在后台时，第一下点击只是“聚焦”，第二下才是“点击”
            // 如果你发现还是点不中，可以尝试把下面这段注释打开：
            /*
            usleep(50000) // 等 50ms
            eventDown.post(tap: .cghidEventTap)
            usleep(10000)
            eventUp.post(tap: .cghidEventTap)
            */
        }
    }

    func handleInput(_ char: String) {
        inputBuffer += char.uppercased()

        if let match = collectedElements.first(where: { $0.id == inputBuffer }) {
            let error = AXUIElementPerformAction(match.rawElement, kAXPressAction as CFString)
            if error != .success {
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
            suspendWindow()  // Just hide UI, don't cancel pending restart
            simulateMouseClick(at: match.frame, targetElement: match)

            if isContinuousMode {
                let item = DispatchWorkItem { [weak self] in
                    self?.start()
                }
                pendingRestartWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            }

        } else {
            let hasPotential = collectedElements.contains { $0.id.hasPrefix(inputBuffer) }
            if !hasPotential {
                inputBuffer = ""
                NSSound.beep()
            }
        }
        window?.contentView?.needsDisplay = true
    }
}
