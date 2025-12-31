import Cocoa

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            AppController.shared.hideWindow()
            return
        }
        if let chars = event.characters, !chars.isEmpty {
            AppController.shared.handleInput(chars)
        }
    }
}
