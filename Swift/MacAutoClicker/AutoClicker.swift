import Foundation
import AppKit
import Quartz

enum MouseButton: String, CaseIterable, Identifiable {
    case left, right, middle
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        }
    }
    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }
    var downType: CGEventType {
        switch self {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        case .middle: return .otherMouseDown
        }
    }
    var upType: CGEventType {
        switch self {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .middle: return .otherMouseUp
        }
    }
}

final class AutoClicker {
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "autoclicker.timer", qos: .userInitiated)
    private var remaining: Int = 0
    private var running = false

    func start(interval: Double, count: Int, button: MouseButton) {
        stop()
        running = true
        remaining = max(0, count)

        let dt = max(0.001, interval)
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: dt)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            if !self.running { return }
            self.click(button: button)
            if self.remaining > 0 {
                self.remaining -= 1
                if self.remaining == 0 {
                    self.stop()
                }
            }
        }
        timer = t
        t.resume()
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
    }

    private func click(button: MouseButton) {
        // Use current cursor position in global screen coordinates
        let loc = NSEvent.mouseLocation

        if let down = CGEvent(mouseEventSource: nil, mouseType: button.downType, mouseCursorPosition: loc, mouseButton: button.cgButton) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: nil, mouseType: button.upType, mouseCursorPosition: loc, mouseButton: button.cgButton) {
            up.post(tap: .cghidEventTap)
        }
    }
}
