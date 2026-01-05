import Cocoa

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            AppController.shared.hideWindow()
            return
        }
        if event.keyCode == 48 { // Tab
            AppController.shared.toggleContinuousMode()
            return
        }
        if let chars = event.characters, !chars.isEmpty {
            AppController.shared.handleInput(chars)
        }
    }
}
