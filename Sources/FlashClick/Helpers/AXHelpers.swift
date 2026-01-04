import Cocoa
import ApplicationServices

class AXHelpers {
    
    static func getAttribute(element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success { return value }
        return nil
    }
    
    static func generateLabel(index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var result = ""
        var i = index
        repeat {
            let remainder = i % 26
            result = String(letters[remainder]) + result
            i = i / 26 - 1
        } while i >= 0
        return result
    }
    
    static func getMultipleAttributes(element: AXUIElement, attributes: [String]) -> [String: Any] {
        var values: CFArray?
        let attrNames = attributes.map { $0 as CFString } as CFArray
        
        let result = AXUIElementCopyMultipleAttributeValues(element, attrNames, [], &values)
        
        var dict: [String: Any] = [:]
        
        if result == .success, let array = values as? [Any], array.count == attributes.count {
            for (index, attr) in attributes.enumerated() {
                let value = array[index]
                
                // 【修改点】去掉 "as CFTypeRef"，直接传 value
                // 因为 value 已经是 AnyObject 了，编译器知道它可以直接转为 CFTypeRef
                if CFGetTypeID(value as! CFTypeRef) == AXValueGetTypeID() {
                    dict[attr] = value
                } 
                else if !(value is NSNull) {
                    dict[attr] = value
                }
            }
        }
        
        return dict
    }
}
