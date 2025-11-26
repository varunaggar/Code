import Foundation
import ApplicationServices

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func promptForTrust() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
