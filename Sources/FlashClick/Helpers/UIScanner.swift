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

        // 优先获取焦点窗口
        var targetWindow: AXUIElement?
        if let focused = AXHelpers.getAttribute(
            element: appElement, attribute: kAXFocusedWindowAttribute as String)
        {
            targetWindow = (focused as! AXUIElement)
        } else if let windows = AXHelpers.getAttribute(
            element: appElement, attribute: kAXWindowsAttribute as String) as? [AXUIElement],
            let first = windows.first
        {
            targetWindow = first
        }

        if let window = targetWindow {
            // 获取窗口范围 (用于裁剪)
            var winPos: CGPoint = .zero
            var winSize: CGSize = .zero

            if let posVal = AXHelpers.getAttribute(
                element: window, attribute: kAXPositionAttribute as String)
            {
                AXValueGetValue(posVal as! AXValue, .cgPoint, &winPos)
            }
            if let sizeVal = AXHelpers.getAttribute(
                element: window, attribute: kAXSizeAttribute as String)
            {
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &winSize)
            }
            let windowRect = CGRect(origin: winPos, size: winSize)

            // --- 阶段 1: 遍历 (Traversal) ---
            let t1: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
            traverse(element: window, list: &elements, visibleRect: windowRect, depth: 0)
            let t2 = CFAbsoluteTimeGetCurrent()

            print(
                String(
                    format: "[⏱️ 遍历耗时] %.4fs (访问节点: %d, 最大深度: %d, 初步收集: %d)", t2 - t1, visitedCount,
                    maxDepthReached, elements.count))
        }

        // --- 阶段 2: 空间去重 (Deduplication) ---
        let t3: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        let deduplicated = deduplicate(elements: elements)
        let t4 = CFAbsoluteTimeGetCurrent()

        print(String(format: "[⏱️ 去重耗时] %.4fs (剩余: %d)", t4 - t3, deduplicated.count))

        // --- 阶段 3: 可见性检测 (PID Check) ---
        let t5 = CFAbsoluteTimeGetCurrent()
        let finalElements: [UIElement] = filterVisibleElements(
            elements: deduplicated, appPID: frontApp.processIdentifier)
        let t6 = CFAbsoluteTimeGetCurrent()

        print(String(format: "[⏱️ PID校验] %.4fs (最终剩余: %d)", t6 - t5, finalElements.count))
        print(String(format: "[🔥 总耗时] %.4fs", t6 - startTime))

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

        // --- 3. 目标角色筛选 ---
        let targetRoles = [
            "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
            "AXPopUpButton", "AXComboBox", "AXRadioButton", "AXTabButton",
            "AXMenuButton", "AXMenuItem", "AXGroup", "AXImage", "AXRow",
            "AXStaticText",  // VS Code 有些按钮其实是可点击的文本
        ]

        if targetRoles.contains(role) {

            // --- 4. 按需检查 Action (核心修改) ---

            // 【修改点 1】扩大信任名单
            // VS Code 的侧边栏图标通常是 AXRadioButton
            // 编辑器 Tab 是 AXTabButton
            // 菜单项是 AXMenuItem
            let trustedRoles = [
                "AXButton", "AXLink", "AXTextField", "AXTextArea",
                "AXCheckBox", "AXRadioButton", "AXMenuItem",
                "AXTabButton", "AXMenuButton", "AXPopUpButton", "AXComboBox",
            ]
            let isTrusted = trustedRoles.contains(role)

            var isValid = false

            if isTrusted {
                isValid = true
            } else {
                // 【修改点 2】对于不信任的角色 (Group, Image, StaticText)，必须查 Action
                var actionNames: CFArray?
                let err = AXUIElementCopyActionNames(element, &actionNames)
                if err == .success, let names = actionNames as? [String], names.count > 0 {
                    isValid = true
                }
            }

            if isValid {
                // ... (尺寸检查代码不变) ...
                if elementFrame.width > 5 && elementFrame.height > 5 && elementFrame.width < 2000
                    && elementFrame.height < 2000
                {
                    let node = UIElement(
                        id: "", role: role, frame: elementFrame, rawElement: element)
                    list.append(node)
                }
            }
        }

        // --- 5. 递归 (修复版) ---

        var children: [AXUIElement] = []

        // 【关键修改】优先尝试获取 "AXVisibleChildren"
        // 这行代码会告诉 App：“只把屏幕上这 4916 个里能看见的那 10 个给我”
        if let visibleRefs = AXHelpers.getAttribute(
            element: element, attribute: "AXVisibleChildren") as? [AXUIElement]
        {
            children = visibleRefs
            // 调试日志：如果成功拿到了可见子节点，打印一下数量对比
            // print("✨ [深度 \(depth)] 成功获取可见子节点: \(children.count) 个 (原本可能有几千个)")
        }
        // 如果 App 不支持 (比如原生 Finder)，再降级获取所有
        else if let allRefs = AXHelpers.getAttribute(
            element: element, attribute: kAXChildrenAttribute as String) as? [AXUIElement]
        {
            children = allRefs
        }

        var nodesToScan = children

        // 如果子节点太多 (超过 300 个)，我们假设中间的都在屏幕外，只扫两头
        if children.count > 300 {
            print("⚠️ [深度 \(depth)] 触发掐头去尾优化: \(children.count) -> 200")
            let head = children.prefix(100)
            let tail = children.suffix(100)
            nodesToScan = Array(head) + Array(tail)
        }

        // 遍历优化后的列表
        for child in nodesToScan {
            if role == "AXRow" { continue }
            traverse(element: child, list: &list, visibleRect: currentVisibleRect, depth: depth + 1)
        }
    }

    // 空间去重算法
    private static func deduplicate(elements: [UIElement]) -> [UIElement] {
        var result: [UIElement] = []

        for item in elements {
            let isRedundant = result.contains { existing in
                let intersection = existing.frame.intersection(item.frame)
                if intersection.isNull { return false }

                let itemArea = item.frame.width * item.frame.height
                let intersectArea = intersection.width * intersection.height
                let ratio1 = intersectArea / itemArea

                // 如果新元素 90% 以上都在旧元素里面
                if ratio1 > 0.9 {
                    let weakRoles = ["AXStaticText", "AXImage", "AXGroup"]
                    if weakRoles.contains(item.role) {
                        return true
                    }
                }

                // 如果两者互相覆盖都超过 80%
                let existingArea = existing.frame.width * existing.frame.height
                let ratio2 = intersectArea / existingArea
                if ratio1 > 0.8 && ratio2 > 0.8 {
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
