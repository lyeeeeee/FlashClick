import Cocoa

class OverlayView: NSView {
    // 数据源
    var elements: [UIElement] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let screenHeight = NSScreen.main?.frame.height else { return }

        let labelColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 0.7)
        let textColor = NSColor.black
        let font = NSFont.boldSystemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        for item in elements {
            let axY = item.frame.origin.y
            let height = item.frame.height
            let cocoaY = screenHeight - axY - height

            let charWidth: CGFloat = 7
            let padding: CGFloat = 8

            let labelWidth: CGFloat = padding + (CGFloat(item.id.count) * charWidth)
            let labelHeight: CGFloat = 14
            
            // --- 【修改点】左上角内缩 20% ---
            
            // 1. 计算偏移量 (宽度的 20%，但最大不超过 12px，防止大窗口标签跑偏)
            let offsetX = min(item.frame.width * 0.2, 12.0)
            let offsetY = min(item.frame.height * 0.2, 12.0)
            
            // 2. 计算 X: 左边缘 + 偏移
            let x = item.frame.origin.x + offsetX
            
            // 3. 计算 Y: 顶边缘 - 偏移 - 标签高度
            // (CocoaY + height = 视觉上的顶部)
            let y = (cocoaY + height) - offsetY - labelHeight
            
            let labelRect = CGRect(x: x, y: y, width: labelWidth, height: labelHeight)

            let path = NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3)
            labelColor.set()
            path.fill()

            let text = item.id as NSString
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: labelRect.origin.x + (labelRect.width - textSize.width) / 2,
                y: labelRect.origin.y + (labelRect.height - textSize.height) / 2 - 1,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
