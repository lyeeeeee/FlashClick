import ApplicationServices
import Cocoa

class UIScanner {

    // 用于统计遍历了多少个节点
    static var visitedCount = 0
    static var maxDepthReached = 0  // 【新增】记录最大深度

    // 扫描入口
    static func scanCurrentWindow() -> [UIElement] {
        let startTime = CFAbsoluteTimeGetCurrent()
        visitedCount = 0

        var elements: [UIElement] = []

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 【修改】获取所有窗口，而不仅仅是焦点窗口
        var targetWindows: [AXUIElement] = []
        if let windows = AXHelpers.getAttribute(
            element: appElement, attribute: kAXWindowsAttribute as String) as? [AXUIElement]
        {
            targetWindows = windows
        } else if let focused = AXHelpers.getAttribute(
            element: appElement, attribute: kAXFocusedWindowAttribute as String)
        {
            targetWindows = [focused as! AXUIElement]
        }

        // 如果没有找到窗口，直接返回
        if targetWindows.isEmpty { return [] }

        // 获取主屏幕范围 (用于过滤屏幕外的窗口)
        let screenFrame = NSScreen.main?.frame ?? CGRect.zero

        // --- 阶段 1: 遍历所有可见窗口 ---
        let t1: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

        for window in targetWindows {
            // 检查是否最小化
            if let minimized = AXHelpers.getAttribute(
                element: window, attribute: kAXMinimizedAttribute as String) as? Bool, minimized
            {
                continue
            }

            // 获取窗口范围 (用于裁剪)
            var windowRect: CGRect = .zero

            // 获取窗口位置
            if let posVal: CFTypeRef = AXHelpers.getAttribute(
                element: window, attribute: kAXPositionAttribute as String)
            {
                var winPos: CGPoint = .zero
                AXValueGetValue(posVal as! AXValue, .cgPoint, &winPos)
                windowRect.origin = winPos
            }

            // 获取窗口大小
            if let sizeVal = AXHelpers.getAttribute(
                element: window, attribute: kAXSizeAttribute as String)
            {
                var winSize: CGSize = .zero
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &winSize)
                windowRect.size = winSize
            }

            // 过滤无效或不可见窗口
            if windowRect.width < 10 || windowRect.height < 10 { continue }
            // 简单的屏幕相交测试 (可选)
            // if !windowRect.intersects(screenFrame) { continue }

            traverse(element: window, list: &elements, visibleRect: windowRect, depth: 0)
        }

        let t2 = CFAbsoluteTimeGetCurrent()

        FileLogger.shared.log(
            String(
                format: "[⏱️ 遍历耗时] %.4fs (窗口数: %d, 访问节点: %d, 最大深度: %d, 初步收集: %d)",
                t2 - t1, targetWindows.count, visitedCount, maxDepthReached, elements.count))

        // --- 阶段 2: 空间去重 (Deduplication) ---
        let t3: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        let deduplicated = deduplicate(elements: elements)
        let t4 = CFAbsoluteTimeGetCurrent()

        FileLogger.shared.log(
            String(format: "[⏱️ 去重耗时] %.4fs (剩余: %d)", t4 - t3, deduplicated.count))

        // --- 阶段 3: 可见性检测 (PID Check) ---
        let t5 = CFAbsoluteTimeGetCurrent()
        let finalElements: [UIElement] = filterVisibleElements(
            elements: deduplicated, appPID: frontApp.processIdentifier)
        let t6 = CFAbsoluteTimeGetCurrent()

        FileLogger.shared.log(
            String(format: "[⏱️ PID校验] %.4fs (最终剩余: %d)", t6 - t5, finalElements.count))
        FileLogger.shared.log(String(format: "[🔥 总耗时] %.4fs", t6 - startTime))

        return finalElements
    }

    // 递归遍历
    private static func traverse(
        element: AXUIElement, list: inout [UIElement], visibleRect: CGRect, depth: Int
    ) {
        visitedCount += 1
        if depth > maxDepthReached {
            maxDepthReached = depth
        }
        // 深度限制 (建议开启，防止 Electron 无限递归)
        if depth > 50 { return }

        // --- 1. 批量获取属性 ---
        let attrs = AXHelpers.getMultipleAttributes(
            element: element,
            attributes: [
                kAXRoleAttribute as String,
                kAXPositionAttribute as String,
                kAXSizeAttribute as String,
            ])

        guard let role = attrs[kAXRoleAttribute as String] as? String else { return }

        // --- 2. 快速位置检查 (剪枝) ---
        var elementFrame = CGRect.zero

        if let posVal = attrs[kAXPositionAttribute as String],
            let sizeVal = attrs[kAXSizeAttribute as String]
        {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            elementFrame = CGRect(origin: pos, size: size)
        }

        // 计算当前元素的可见区域
        let currentVisibleRect = visibleRect.intersection(elementFrame)

        // 如果完全不可见或太小，停止递归
        if currentVisibleRect.isNull || currentVisibleRect.width < 5
            || currentVisibleRect.height < 5
        {
            return
        }

        // --- 3. 目标角色筛选和验证 ---
        // 所有需要处理的角色
        let allRoles = [
            "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
            "AXPopUpButton", "AXComboBox", "AXRadioButton", "AXTabButton",
            "AXMenuButton", "AXMenuItem", "AXGroup", "AXImage", "AXRow",
            "AXStaticText",  // VS Code 有些按钮其实是可点击的文本
        ]

        // 信任的角色（无需额外检查action）
        let trustedRoles = Set([
            "AXButton", "AXLink", "AXTextField", "AXTextArea",
            "AXCheckBox", "AXRadioButton", "AXMenuItem",
            "AXTabButton", "AXMenuButton", "AXPopUpButton", "AXComboBox",
        ])

        if allRoles.contains(role) {
            // --- 4. 按需检查 Action ---
            var isValid = false

            if trustedRoles.contains(role) {
                isValid = true
            } else {
                // 对于不信任的角色 (Group, Image, StaticText)，必须查 Action
                var actionNames: CFArray?
                let err: AXError = AXUIElementCopyActionNames(element, &actionNames)
                if err == .success, let names: [String] = actionNames as? [String], names.count > 0
                {
                    isValid = true
                }
            }

            if isValid {
                // 检查元素大小上限（下限已在可见性检查中处理）
                if elementFrame.width < 2000 && elementFrame.height < 2000 {
                    let node = UIElement(
                        id: "", role: role, frame: elementFrame, rawElement: element)
                    list.append(node)
                }
            }
        }

        // --- 5. 递归 (修复版) ---

        var children: [AXUIElement] = []

        // 优先尝试获取 "AXVisibleChildren"
        if let visibleRefs: [AXUIElement] = AXHelpers.getAttribute(
            element: element, attribute: "AXVisibleChildren") as? [AXUIElement]
        {
            children = visibleRefs
        }
        // 如果 App 不支持 (比如原生 Finder)，再降级获取所有
        else if let allRefs: [AXUIElement] = AXHelpers.getAttribute(
            element: element, attribute: kAXChildrenAttribute as String) as? [AXUIElement]
        {
            children = allRefs
        }

        var nodesToScan: [AXUIElement] = children

        // 如果子节点太多，只扫两头
        if children.count > 400 {
            FileLogger.shared.log("⚠️ [深度 \(depth)] 触发掐头去尾优化: \(children.count) -> 200")
            let head: Array<AXUIElement>.SubSequence = children.prefix(200)
            let tail: Array<AXUIElement>.SubSequence = children.suffix(200)
            nodesToScan = Array(head) + Array(tail)
        }

        // 遍历优化后的列表
        for child: AXUIElement in nodesToScan {
            //if role == "AXRow" { continue }
            traverse(element: child, list: &list, visibleRect: currentVisibleRect, depth: depth + 1)
        }
    }

    // 空间去重算法
    private static func deduplicate(elements: [UIElement]) -> [UIElement] {
        var result: [UIElement] = []

        for item: UIElement in elements {
            // 计算当前item的面积（只计算一次）
            let itemArea = item.frame.width * item.frame.height

            let isRedundant = result.contains { existing in
                let intersection = existing.frame.intersection(item.frame)
                if intersection.isNull { return false }

                let intersectArea = intersection.width * intersection.height
                let ratio1 = intersectArea / itemArea

                // 计算现有元素的面积
                let existingArea = existing.frame.width * existing.frame.height
                let ratio2 = intersectArea / existingArea

                // 如果两者互相覆盖都超过 10%
                if ratio1 > 0.1 && ratio2 > 0.1 {
                    return true
                }

                return false
            }

            if !isRedundant {
                result.append(item)
            }
        }
        return result
    }

    // 点击穿透检测
    private static func filterVisibleElements(elements: [UIElement], appPID: pid_t) -> [UIElement] {
        let systemWide: AXUIElement = AXUIElementCreateSystemWide()
        var visibleElements: [UIElement] = []

        for item in elements {
            let centerX = item.frame.origin.x + item.frame.width / 2
            let centerY = item.frame.origin.y + item.frame.height / 2

            var hitElement: AXUIElement?
            let err = AXUIElementCopyElementAtPosition(
                systemWide, Float(centerX), Float(centerY), &hitElement)

            if err == .success, let hit = hitElement {
                var hitPID: pid_t = 0
                AXUIElementGetPid(hit, &hitPID)
                if hitPID == appPID {
                    visibleElements.append(item)
                }
            } else {
                visibleElements.append(item)
            }
        }
        return visibleElements
    }
}
