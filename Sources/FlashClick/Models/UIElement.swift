import Cocoa
import ApplicationServices

struct UIElement {
    var id: String
    let role: String
    let frame: CGRect
    let rawElement: AXUIElement
}
