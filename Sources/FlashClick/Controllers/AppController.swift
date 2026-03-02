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
        // 1. 获取鼠标当前所在的屏幕
        let mouseLoc = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main
        let screenFrame = currentScreen?.frame ?? CGRect.zero
        
        // 2. 扫描该屏幕上的元素
        collectedElements = UIScanner.scanCurrentWindow(screen: currentScreen)

        if collectedElements.isEmpty {
            FileLogger.shared.log("⚠️ 未找到元素")
            NSSound.beep()
            return
        }

        // 3. 排序：以鼠标位置为中心
        let center = mouseLoc
        collectedElements.sort { (node1, node2) -> Bool in
            let dist1 = hypot(node1.frame.midX - center.x, node1.frame.midY - center.y)
            let dist2 = hypot(node2.frame.midX - center.x, node2.frame.midY - center.y)
            return dist1 < dist2
        }

        // 分配标签
        for i in 0..<collectedElements.count {
            collectedElements[i].id = AXHelpers.generateLabel(index: i)
        }

        // 4. 显示窗口 (强制显示在当前屏幕)
        showWindow(at: screenFrame)
    }

    func showWindow(at targetFrame: CGRect) {
        // 1. 找到包含目标元素的屏幕
        let targetScreen =
            NSScreen.screens.first { screen in
                let intersection = NSIntersectionRect(screen.frame, targetFrame)
                return intersection.width * intersection.height > 0
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
            let hasPotential: Bool = collectedElements.contains { $0.id.hasPrefix(inputBuffer) }
            if !hasPotential {
                inputBuffer = ""
                NSSound.beep()
            }
        }
        window?.contentView?.needsDisplay = true
    }

    enum ScrollDirection {
        case up
        case down
    }

    // Scroll state
    private var lastScrollCommandTime: Date = Date.distantPast
    private var cachedScrollLocation: CGPoint?
    private var scrollVelocityY: Double = 0.0
    private var scrollTimer: Timer?
    private var activeScrollKeyCode: CGKeyCode?  // Store which key triggered the scroll

    // Physics parameters
    private let holdingFriction: Double = 0.98  // Low friction while holding
    private let releaseFriction: Double = 0.85  // Higher friction when released (stopped faster)
    private let velocityImpulse: Double = 5.0  // Lower initial impulse for smoother tap
    private let maxVelocity: Double = 30.0  // Cap max speed to avoid dizziness

    func scroll(direction: ScrollDirection, keyCode: CGKeyCode? = nil) {
        let now = Date()

        // Update cache if command gap is large (new scroll session)
        // or if we haven't updated in a while (to handle window movement)
        if now.timeIntervalSince(lastScrollCommandTime) > 0.5 {
            cachedScrollLocation = getScrollTargetLocation()
        }
        lastScrollCommandTime = now
        activeScrollKeyCode = keyCode  // Store the key code

        // If changing direction, reset velocity immediately for responsiveness
        if (direction == .up && scrollVelocityY < 0) || (direction == .down && scrollVelocityY > 0)
        {
            scrollVelocityY = 0
        }

        // Apply impulse
        let impulse = direction == .up ? velocityImpulse : -velocityImpulse
        scrollVelocityY += impulse

        // Clamp velocity
        if scrollVelocityY > maxVelocity { scrollVelocityY = maxVelocity }
        if scrollVelocityY < -maxVelocity { scrollVelocityY = -maxVelocity }

        // Start animation timer if not running
        if scrollTimer == nil {
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
                [weak self] _ in
                self?.handleScrollTick()
            }
        }
    }

    private func handleScrollTick() {
        // Check if user is still holding the key
        var isHolding = false

        if let keyCode = activeScrollKeyCode {
            // Check specific key state (requires permission but we have it for accessibility)
            isHolding = CGEventSource.keyState(.combinedSessionState, key: keyCode)
        } else {
            // Fallback: Check if recent command received (for non-key sources or missing keycode)
            let timeSinceLastCommand = Date().timeIntervalSince(lastScrollCommandTime)
            isHolding = timeSinceLastCommand < 0.15
        }

        // Apply different friction based on state
        let currentFriction = isHolding ? holdingFriction : releaseFriction

        // Apply friction FIRST to avoid infinite speed accumulation during holding
        scrollVelocityY *= currentFriction

        // If holding, add a small continuous force to maintain speed against friction
        // This simulates "pushing" the wheel constantly
        if isHolding {
            // Add a small force in the direction of velocity
            let force = (scrollVelocityY > 0 ? 1.0 : -1.0) * (velocityImpulse * 0.1)
            scrollVelocityY += force

            // Re-clamp
            if scrollVelocityY > maxVelocity { scrollVelocityY = maxVelocity }
            if scrollVelocityY < -maxVelocity { scrollVelocityY = -maxVelocity }
        }

        // Apply natural scrolling logic
        let isNatural = isNaturalScrollingEnabled()
        let finalDelta = Int32(isNatural ? -scrollVelocityY : scrollVelocityY)

        // Send event
        if abs(finalDelta) > 0,
            let source = CGEventSource(stateID: .hidSystemState),
            let scrollEvent = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: finalDelta,
                wheel2: 0,
                wheel3: 0
            )
        {

            if let location = cachedScrollLocation {
                scrollEvent.location = location
            } else if let currentEvent = CGEvent(source: nil) {
                scrollEvent.location = currentEvent.location
            }

            scrollEvent.post(tap: .cghidEventTap)
        }

        // Stop condition:
        // Only stop if NOT holding AND velocity is very low
        if !isHolding && abs(scrollVelocityY) < 1.0 {  // Increased threshold to stop sooner
            scrollTimer?.invalidate()
            scrollTimer = nil
            scrollVelocityY = 0
            activeScrollKeyCode = nil
        }
    }

    private func getScrollTargetLocation() -> CGPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Try to get focused window
        if let focusedWindow = AXHelpers.getAttribute(
            element: appElement, attribute: kAXFocusedWindowAttribute as String)
        {
            let window = focusedWindow as! AXUIElement
            // Get position and size to calculate center
            if let posVal = AXHelpers.getAttribute(
                element: window, attribute: kAXPositionAttribute as String),
                let sizeVal = AXHelpers.getAttribute(
                    element: window, attribute: kAXSizeAttribute as String)
            {

                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

                return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
            }
        }

        return nil
    }

    private func isNaturalScrollingEnabled() -> Bool {
        let key = "com.apple.swipescrolldirection" as CFString
        // kCFPreferencesAnyApplication is not directly available in Swift easily without import,
        // but we can use CFPreferencesCopyAppValue with specific domain
        // However, "NSGlobalDomain" works via UserDefaults too usually, but CFPreferences is safer for global settings
        if let value = CFPreferencesCopyAppValue(key, "NSGlobalDomain" as CFString) {
            return (value as? Bool) ?? true
        }
        return true  // Default to true on modern macOS
    }
}
