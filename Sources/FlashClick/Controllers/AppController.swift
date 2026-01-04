import Cocoa
import ApplicationServices

class AppController {
    static let shared = AppController()
    
    var window: OverlayWindow?
    var collectedElements: [UIElement] = []
    var inputBuffer = ""
    
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    
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
                  let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            
            if app.processIdentifier == getpid() { return }
            self?.hideWindow()
        }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideWindow()
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.hideWindow()
            return event
        }
    }
    
    func start() {
        print("🚀 正在扫描...")
        collectedElements = UIScanner.scanCurrentWindow()
        
        if collectedElements.isEmpty {
            print("⚠️ 未找到元素")
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
        let targetScreen = NSScreen.screens.first { screen in
            NSIntersectionRect(screen.frame, targetFrame) != .zero
        } ?? NSScreen.main ?? NSScreen.screens[0]
        
        let screenRect = targetScreen.frame
        
        if window == nil {
            window = OverlayWindow(contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
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
        window?.orderOut(nil)
        NSApplication.shared.hide(nil)
        inputBuffer = ""
    }
    
    func handleInput(_ char: String) {
        inputBuffer += char.uppercased()
        
        if let match = collectedElements.first(where: { $0.id == inputBuffer }) {
            let error = AXUIElementPerformAction(match.rawElement, kAXPressAction as CFString)
            if error != .success {
                let centerX = match.frame.origin.x + match.frame.width / 2
                let centerY = match.frame.origin.y + match.frame.height / 2
                let point = CGPoint(x: centerX, y: centerY)
                let eventDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
                let eventUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
                eventDown?.post(tap: .cghidEventTap)
                usleep(10000)
                eventUp?.post(tap: .cghidEventTap)
            }
            hideWindow()
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
