import AppKit
import ApplicationServices
import CoreGraphics

/// Pastes a text string into whatever application was last focused.
///
/// Steps:
///   1. Write `text` to the general pasteboard.
///   2. Re-activate the last focused application.
///   3. After a short delay (for app-switch animation), post Cmd+V via CGEvent.
///
/// **Requires Accessibility permission** (`NSAccessibilityUsageDescription` in Info.plist).
/// Without it, `CGEventPost` silently does nothing.
enum Paster {

    /// Virtual key code for V on a US-layout keyboard (carbon constant kVK_ANSI_V = 9).
    private static let kVK_ANSI_V: CGKeyCode = 9

    static func paste(text: String, focusTracker: FocusTracker) {
        // 1. Write to pasteboard.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSLog("[Paster] copied %d chars to pasteboard", text.count)

        // 2. Re-activate the target application.
        guard let target = focusTracker.lastFocusedApp else {
            NSLog("[Paster] no previous app recorded — text is on clipboard only")
            return
        }

        // Without Accessibility trust, CGEventPost silently no-ops. Detect
        // and log instead of failing silently — TCC drops the grant whenever
        // the unsigned binary changes (every rebuild via build.sh).
        if !AXIsProcessTrusted() {
            NSLog("[Paster] ⚠️ Accessibility NOT trusted — Cmd+V will silently fail. Re-grant in System Settings → Privacy & Security → Accessibility. Text remains on clipboard for manual ⌘V.")
            target.activate(options: .activateIgnoringOtherApps)
            return
        }

        // Deactivate ourselves first so the floating, key-capable window
        // releases focus before the target activates. Without this, Cmd+V
        // can race and land in our own input field instead of the target.
        NSApp.deactivate()
        target.activate(options: .activateIgnoringOtherApps)
        NSLog("[Paster] activating %@, posting ⌘V in 120 ms", target.localizedName ?? "?")

        // 3. Post Cmd+V after giving the OS time to complete the app switch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            sendCmdV()
        }
    }

    // MARK: - CGEvent helpers

    private static func sendCmdV() {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: kVK_ANSI_V, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: kVK_ANSI_V, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
