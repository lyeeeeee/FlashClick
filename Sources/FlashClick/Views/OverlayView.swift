import Cocoa

class OverlayView: NSView {
    var elements: [UIElement] = []
    
    override func draw(_ dirtyRect: NSRect) {
        // 【核心修改】永远使用主屏幕高度做基准
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return }
        
        let labelColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 0.85)
        let borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.2)
        let textColor = NSColor.black
        let font = NSFont.boldSystemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        var occupiedRects: [CGRect] = []
        
        for item in elements {
            let axY = item.frame.origin.y
            let height = item.frame.height
            
            // 【核心修改】计算全局 Cocoa 坐标
            let globalCocoaY = primaryScreenHeight - axY - height
            let globalPoint = CGPoint(x: item.frame.origin.x, y: globalCocoaY)
            
            // 【核心修改】转换为当前窗口的本地坐标 (自动处理多屏偏移)
            let localPoint = self.window?.convertPoint(fromScreen: globalPoint) ?? globalPoint
            
            let charWidth: CGFloat = 7
            let padding: CGFloat = 8
            let labelWidth: CGFloat = padding + (CGFloat(item.id.count) * charWidth)
            let labelHeight: CGFloat = 16
            
            // 智能定位
            var x: CGFloat = 0
            var y: CGFloat = 0
            
            let isFlatItem = item.frame.height < 50 && item.frame.width > item.frame.height * 2
            
            if isFlatItem {
                x = localPoint.x + 4
                y = localPoint.y + (height - labelHeight) / 2
            } else {
                let offsetX = min(item.frame.width * 0.2, 12.0)
                let offsetY = min(item.frame.height * 0.2, 12.0)
                x = localPoint.x + offsetX
                y = (localPoint.y + height) - offsetY - labelHeight
            }
            
            var labelRect = CGRect(x: x, y: y, width: labelWidth, height: labelHeight)
            
            // 防碰撞检测
            let maxAttempts = 5
            var attempt = 0
            while attempt < maxAttempts {
                var intersects = false
                for occupied in occupiedRects {
                    if labelRect.intersects(occupied.insetBy(dx: -1, dy: -1)) {
                        intersects = true
                        break
                    }
                }
                if !intersects { break }
                labelRect.origin.x += (labelWidth + 2)
                attempt += 1
            }
            occupiedRects.append(labelRect)
            
            // 绘制
            let path = NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3)
            labelColor.set()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()
            
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
        
        // Draw Continuous Mode Indicator
        if AppController.shared.isContinuousMode {
            let statusText = "Continuous Mode (Tab to toggle)" as NSString
            let statusAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.6)
            ]
            let size = statusText.size(withAttributes: statusAttributes)
            // Draw at bottom right
            let rect = CGRect(
                x: self.bounds.width - size.width - 20, 
                y: 20, 
                width: size.width, 
                height: size.height
            )
            statusText.draw(in: rect, withAttributes: statusAttributes)
        }
    }
}
