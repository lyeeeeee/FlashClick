import Cocoa
import ApplicationServices

class UIScanner {
    // 扫描入口
    static func scanCurrentWindow() -> [UIElement] {
        var elements: [UIElement] = []
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // 优先获取焦点窗口，降级获取第一个窗口
        var targetWindow: AXUIElement?
        
        if let focused = AXHelpers.getAttribute(element: appElement, attribute: kAXFocusedWindowAttribute as String) {
            targetWindow = (focused as! AXUIElement)
        } else if let windows = AXHelpers.getAttribute(element: appElement, attribute: kAXWindowsAttribute as String) as? [AXUIElement], let first = windows.first {
            targetWindow = first
        }
        
        if let window = targetWindow {
            traverse(element: window, list: &elements)
        }
        
        return elements
    }
    
    // 递归遍历 (注意：现在 list 是通过 inout 传递的，不再是全局变量)
    private static func traverse(element: AXUIElement, list: inout [UIElement]) {
        let targetRoles = ["AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox", "AXPopUpButton", "AXComboBox", "AXRadioButton", "AXTabButton", "AXMenuButton", "AXMenuItem", "AXImage"]
        
        if let roleRef = AXHelpers.getAttribute(element: element, attribute: kAXRoleAttribute as String),
           let role = roleRef as? String {
            
            if targetRoles.contains(role) {
                var position: CGPoint = .zero
                var size: CGSize = .zero
                
                if let posVal = AXHelpers.getAttribute(element: element, attribute: kAXPositionAttribute as String) {
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
                }
                if let sizeVal = AXHelpers.getAttribute(element: element, attribute: kAXSizeAttribute as String) {
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
                }
                
                if size.width > 0 && size.height > 0 {
                    // ID 暂时留空，稍后统一生成
                    let node = UIElement(id: "", role: role, frame: CGRect(origin: position, size: size), rawElement: element)
                    list.append(node)
                }
            }
            
            if let childrenRef = AXHelpers.getAttribute(element: element, attribute: kAXChildrenAttribute as String),
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    traverse(element: child, list: &list)
                }
            }
        }
    }
}
