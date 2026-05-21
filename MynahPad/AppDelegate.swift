import AppKit
import ApplicationServices

/// Coordinates all top-level objects. Holds strong references to everything that
/// NSApplication would otherwise release (status bar, window, trackers).
final class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!
    var noteListWindow: NoteListWindow!
    var focusTracker: FocusTracker!
    var store: Store!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — belt-and-suspenders alongside LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // Shared data store.
        store = Store()
        store.load()

        // Focus tracker must start before user can interact.
        focusTracker = FocusTracker()

        // Floating note list window.
        noteListWindow = NoteListWindow(store: store, focusTracker: focusTracker)

        // Status bar icon + menu.
        statusBarController = StatusBarController(
            store: store,
            window: noteListWindow
        )

        // Start update check in the background.
        UpdateChecker.shared.check { [weak self] latestVersion in
            DispatchQueue.main.async {
                self?.statusBarController.showUpdateAvailable(version: latestVersion)
            }
        }

        // Accessibility trust — required for the Cmd+V paste to actually fire.
        // Without it, CGEventPost silently no-ops. Prompt the user once on launch
        // so they can grant it in System Settings → Privacy & Security.
        promptForAccessibilityIfNeeded()
    }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            NSLog("[MynahPad] Accessibility not granted — paste will silently fail until granted.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    /// Window close button hides rather than destroys the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        noteListWindow.showWindow()
        return false
    }
}
