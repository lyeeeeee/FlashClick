import ApplicationServices
import Cocoa

class AXHelpers {
    static func getAttribute(element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success { return value }
        return nil
    }

    static func generateLabel(index: Int) -> String {
        // 1. 所有可用的键位 (Homerow Keys)
        let allKeys = Array("BCEGHIMNOPQRTUVWXYZ")

        // 2. 【配置】你想保留哪些键作为“黄金单字母”？
        // 建议选食指和中指最好按的键，比如 F, J, D, K
        // 注意：这些键一旦被选为单字母，就永远不会作为双字母的“开头”出现
        let singleKeys = Array("ASDFJKL")

        // 3. 剩下的键，将作为“前缀”
        // (比如 A, S, G, H, L, ;)
        let prefixKeys = allKeys.filter { !singleKeys.contains($0) }

        // --- 分配逻辑 ---

        // 阶段一：分配单字母
        if index < singleKeys.count {
            return String(singleKeys[index])
        }

        // 阶段二：分配双字母
        // 我们减去已经消耗掉的单字母数量
        let doubleIndex = index - singleKeys.count

        // 计算前缀和后缀
        // 前缀只能从 prefixKeys 里选
        // 后缀可以从 allKeys 里随便选
        let prefixIndex = doubleIndex / allKeys.count
        let suffixIndex = doubleIndex % allKeys.count

        if prefixIndex < prefixKeys.count {
            let prefix = prefixKeys[prefixIndex]
            let suffix = allKeys[suffixIndex]
            return "\(prefix)\(suffix)"
        }

        // 阶段三：如果按钮实在太多（超过了几百个），就用兜底方案
        return "ZZ"
    }
}
