import AppKit
import ApplicationServices
import Sparkle

/// Coordinates all top-level objects. Holds strong references to everything that
/// NSApplication would otherwise release (status bar, window, trackers).
final class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController!
    var noteListWindow: NoteListWindow!
    var focusTracker: FocusTracker!
    var store: Store!
    var updaterController: SPUStandardUpdaterController!

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

        // Sparkle auto-updater. `startingUpdater: true` schedules the first
        // background check using SUScheduledCheckInterval from Info.plist.
        // The user driver presents native dialogs for "new version available",
        // download progress, and the install-and-relaunch step.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Status bar icon + menu — needs the updater so the "Check for Updates…"
        // menu item can invoke it.
        statusBarController = StatusBarController(
            store: store,
            window: noteListWindow,
            updater: updaterController
        )

        // Wire the in-panel "Update Now" banner button to Sparkle so the user
        // can re-open the native install dialog without using the menu bar.
        UpdateNotifier.shared.onInstallTapped = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }

        // Show the panel on launch so the user sees their notes immediately
        // instead of having to click the menu-bar icon first.
        noteListWindow.showWindow()

        // Accessibility trust — required for the Cmd+V paste to actually fire.
        // Without it, CGEventPost silently no-ops. Prompt the user once on launch
        // so they can grant it in System Settings → Privacy & Security.
        promptForAccessibilityIfNeeded()
    }

    /// First-responder action so any UI hooked to `Selector("checkForUpdates:")`
    /// (menu items, future buttons) routes through the same updater.
    @IBAction func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    private func promptForAccessibilityIfNeeded() {
        // Side-effect-free check first. If the grant is already there for this
        // binary's signing identity, we never bother the user.
        if AXIsProcessTrusted() {
            NSLog("[MynahPad] Accessibility already granted.")
            return
        }

        NSLog("[MynahPad] Accessibility not granted — paste will silently fail until granted.")

        // Defer to the next runloop tick so the alert doesn't race the status
        // bar / window setup happening in applicationDidFinishLaunching.
        DispatchQueue.main.async { [weak self] in
            self?.showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Accessibility access needed"
        alert.informativeText = """
            MynahPad needs Accessibility access to paste notes into the focused window. \
            Without it, copy still works but auto-paste will silently fail.

            If you previously granted permission but still see this dialog, an older \
            build's grant is stale (different code signature). Use "Reset & Grant" to \
            clear it, then re-grant when prompted.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Reset & Grant")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
        case .alertSecondButtonReturn:
            resetAccessibilityGrant()
        default:
            break
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func resetAccessibilityGrant() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mynahpad.app"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        try? task.run()
        task.waitUntilExit()
        openAccessibilitySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        noteListWindow.showWindow()
        return false
    }
}

// MARK: - SPUUpdaterDelegate

extension AppDelegate: SPUUpdaterDelegate {
    /// Fires when Sparkle confirms an appcast entry is newer than the running
    /// build. Surface it in the panel banner and reveal the window so the user
    /// can act even if they dismissed the native dialog.
    ///
    /// We deliberately do NOT hook `didDownloadUpdate` to show a "restart now"
    /// alert: that callback fires before Sparkle has extracted/validated/staged
    /// the update, so quitting at that point relaunches the *old* bundle.
    /// Sparkle's own standard user driver already presents the correct
    /// "Install Update and Relaunch" dialog once the package is fully staged
    /// — we let it handle that step.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            UpdateNotifier.shared.setAvailable(version: item.displayVersionString)
            self.noteListWindow.showWindow()
        }
    }
}
