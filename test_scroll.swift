import Cocoa
import CoreGraphics

let args = CommandLine.arguments
let direction = args.count > 1 ? args[1] : "down"

print("Simulating scroll \(direction)...")

let source = CGEventSource(stateID: .hidSystemState)
let scrollAmount: Int32 = direction == "up" ? 10 : -10

guard let scrollEvent = CGEvent(
    scrollWheelEvent2Source: source,
    units: .line,
    wheelCount: 1,
    wheel1: scrollAmount,
    wheel2: 0,
    wheel3: 0
) else {
    print("Failed to create event")
    exit(1)
}

scrollEvent.post(tap: .cghidEventTap)
print("Scrolled.")
