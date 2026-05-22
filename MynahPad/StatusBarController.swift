import AppKit
import Sparkle

/// Manages the NSStatusItem in the menu bar and its drop-down menu.
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let store: Store
    private weak var window: NoteListWindow?
    private let updater: SPUStandardUpdaterController

    private static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    init(store: Store, window: NoteListWindow, updater: SPUStandardUpdaterController) {
        self.store = store
        self.window = window
        self.updater = updater

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()
        buildMenu()
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = loadMenuBarIcon()
        button.toolTip = "MynahPad"
    }

    /// Prefers the bundled MiniIcon.png (proper template image with the bird
    /// silhouette). Falls back to an SF Symbol, then to a drawn square — both
    /// kept so the app still launches if the asset is missing.
    private func loadMenuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "MiniIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            // Point size for menu-bar status items. macOS renders the high-res
            // bitmap (663x651) downsampled to this size and picks @2x on Retina.
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MynahPad") {
            image.isTemplate = true
            return image
        }
        return makeFallbackIcon()
    }

    private func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Version label (inert).
        let versionItem = NSMenuItem(
            title: "MynahPad \(Self.version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        // Sparkle on-demand update check. Validates against the latest entry
        // in the appcast and presents the native update dialog if newer.
        let checkUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdates.target = self
        menu.addItem(checkUpdates)

        menu.addItem(.separator())

        let showHide = NSMenuItem(
            title: "Show/Hide Window",
            action: #selector(toggleWindow),
            keyEquivalent: "p"
        )
        showHide.keyEquivalentModifierMask = [.command, .shift]
        showHide.target = self
        menu.addItem(showHide)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About MynahPad",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let github = NSMenuItem(
            title: "View on GitHub",
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        github.target = self
        menu.addItem(github)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleWindow() {
        window?.toggleWindow()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let tagline = "A lightweight macOS menu-bar app that pastes text prompts into your terminal with a double-click."
        let credits = NSAttributedString(
            string: tagline,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/90n9/mynah-pad")!)
    }
}
