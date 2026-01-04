import ApplicationServices
import Cocoa

class AXHelpers {

    static func getAttribute(element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success { return value }
        return nil
    }

    // 1. 定义单字符集合 (高频键)
    static let singleCharKeys = Array("ASDFJKL;")

    // 2. 定义所有可用字符 (全键盘 + 分号)
    static let allKeys: [String.Element] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ;")

    // 3. 计算双字符的前缀集合
    // 逻辑：从所有字符中剔除掉已经被单字符占用的键
    // 结果通常是: q, w, e, r, t, y, u, i, o, p, z, x, c, v, b, n, m
    static let doubleCharPrefixKeys: [String.Element] = allKeys.filter {
        !singleCharKeys.contains($0)
    }

    static func generateLabel(index: Int) -> String {
        // --- 第一阶段：单字符 ---
        if index < singleCharKeys.count {
            return String(singleCharKeys[index])
        }

        // --- 第二阶段：双字符 ---
        // 减去已经被单字符消耗掉的 index
        let adjustedIndex: Int = index - singleCharKeys.count

        let prefixCount = doubleCharPrefixKeys.count
        let suffixCount = allKeys.count

        // 检查是否超出双字符能表示的最大范围
        // 容量 = 前缀数量 * 后缀数量
        if adjustedIndex < prefixCount * suffixCount {
            // 计算前缀索引 (商)
            let prefixIndex = adjustedIndex / suffixCount
            // 计算后缀索引 (余数)
            let suffixIndex = adjustedIndex % suffixCount

            return String(doubleCharPrefixKeys[prefixIndex]) + String(allKeys[suffixIndex])
        }

        // --- 第三阶段 (可选)：如果还需要更多，可以在这里扩展三字符逻辑 ---
        return "??"
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
                } else if !(value is NSNull) {
                    dict[attr] = value
                }
            }
        }

        return dict
    }
}
