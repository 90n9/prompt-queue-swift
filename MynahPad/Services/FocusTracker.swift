import AppKit

/// Tracks the last application that was frontmost before MynahPad was activated.
/// Paster uses this to re-focus the target app before simulating Cmd+V.
final class FocusTracker {

    /// The most recent non-MynahPad frontmost application.
    private(set) var lastFocusedApp: NSRunningApplication?

    private let ownPID: pid_t = NSRunningApplication.current.processIdentifier

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            app.processIdentifier != ownPID
        else { return }

        lastFocusedApp = app
    }
}
