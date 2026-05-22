import AppKit
import SwiftUI

// MARK: - Shared view state

/// Shared mutable state bridge between the NSWindow host and the SwiftUI view.
/// Allows `keyDown(with:)` in NoteListWindow to read which note is selected
/// without using `.onKeyPress` (macOS 14+).
final class NoteListViewState: ObservableObject {
    @Published var selectedNoteID: String? = nil
    /// Mirrors the visible folder so the window's keyDown can read it
    /// (for "Cmd+Delete clears used in current folder", etc.).
    @Published var selectedFolderID: String = "general"
    /// When true, the window shrinks to the title-bar only so the panel
    /// can stay floating without blocking content during screen sharing.
    @Published var isMinimized: Bool = false
}

// MARK: - Window

/// A frameless, floating, dark window that hosts the SwiftUI NoteListView.
/// - Stays above other windows but doesn't force exclusive focus.
/// - Closing hides rather than deallocates.
/// - Draggable from anywhere in the titlebar region.
final class NoteListWindow: NSWindow, NSWindowDelegate {

    private let store: Store
    private let focusTracker: FocusTracker

    /// Shared selection state — the SwiftUI view writes here; keyDown reads it.
    private let viewState = NoteListViewState()

    /// Size the window had right before being minimized. Used to restore
    /// the previous frame when the user expands again.
    private var savedExpandedHeight: CGFloat = 500
    private var savedExpandedWidth: CGFloat = 320

    /// Strip dimensions when minimized — logo + minimize + close, nothing else.
    /// Height is sized for the 42pt colourful app icon with 6pt vertical padding.
    private let minimizedHeight: CGFloat = 54
    private let minimizedWidth: CGFloat = 120

    /// Minimum expanded bounds. Mirror the values set in `configureWindow()`.
    private let expandedMinWidth: CGFloat = 280
    private let expandedMinHeight: CGFloat = 350
    private let expandedMaxWidth: CGFloat = 1100
    private let expandedMaxHeight: CGFloat = 1200

    init(store: Store, focusTracker: FocusTracker) {
        self.store = store
        self.focusTracker = focusTracker

        let initialRect: NSRect = {
            let geo = store.windowGeometry
            if geo.x == 0 && geo.y == 0 {
                // Centre on primary screen the first time.
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let sw = screen.visibleFrame.width
                let sh = screen.visibleFrame.height
                let w: CGFloat = CGFloat(geo.w > 0 ? geo.w : 320)
                let h: CGFloat = CGFloat(geo.h > 0 ? geo.h : 500)
                return NSRect(
                    x: screen.visibleFrame.minX + (sw - w) / 2,
                    y: screen.visibleFrame.minY + (sh - h) / 2,
                    width: w,
                    height: h
                )
            }
            return NSRect(x: CGFloat(geo.x), y: CGFloat(geo.y),
                          width: CGFloat(geo.w > 0 ? geo.w : 320),
                          height: CGFloat(geo.h > 0 ? geo.h : 500))
        }()

        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        embedSwiftUI()
        self.delegate = self
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Window itself is clear — NSVisualEffectView (added in embedSwiftUI)
        // provides the Spotlight-style desktop blur.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Force dark appearance so the dark vibrancy material is used and
        // text remains light regardless of the system setting.
        appearance = NSAppearance(named: .darkAqua)

        // Corner radius via contentView layer — clips the vibrancy view too.
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true

        // Floating above regular windows, visible on all spaces
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Allow resizing
        minSize = NSSize(width: 280, height: 350)
        maxSize = NSSize(width: 1100, height: 1200)

        // Window drags from any background region. Note rows opt out of this
        // via NoWindowDragRegion so .draggable doesn't compete with the move.
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Standard close/min/zoom buttons removed (borderless)
        // Esc and Delete key handling lives in keyDown(with:) below.
    }

    // MARK: - Keyboard

    // Borderless windows return false for canBecomeKey by default, which blocks
    // keyboard input to embedded text fields. Override so the input bar can type.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:  // Esc
            hideWindow()
            return
        case 51, 117:  // Delete (backspace=51) / Forward-Delete (117)
            if event.modifierFlags.contains(.command) {
                // Cmd+Delete: clear all used notes in the current folder.
                store.deleteUsedNotes(in: viewState.selectedFolderID)
                return
            }
            if let noteID = viewState.selectedNoteID {
                store.deleteNote(id: noteID)
                viewState.selectedNoteID = nil
                return
            }
        default:
            // Digits 1–9 move the selected note to folder N (1-indexed).
            if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
               let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), (1...9).contains(digit),
               let noteID = viewState.selectedNoteID,
               digit <= store.folders.count {
                let target = store.folders[digit - 1]
                store.moveNote(id: noteID, toFolder: target.id)
                viewState.selectedFolderID = target.id
                return
            }
        }
        super.keyDown(with: event)
    }

    private func embedSwiftUI() {
        guard let cv = contentView else { return }

        // Vibrancy layer — blurs the desktop behind the window, like Spotlight
        // and Notification Center. `.hudWindow` gives the dark, slightly tinted
        // material; `.behindWindow` blends with what's behind the app window.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(blur)

        let rootView = NoteListView(
            store: store,
            focusTracker: focusTracker,
            viewState: viewState,
            onHide: { [weak self] in self?.hideWindow() },
            onToggleMinimize: { [weak self] in self?.toggleMinimize() }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Ensure the SwiftUI host doesn't paint a solid background that would
        // block the vibrancy layer below it.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        cv.addSubview(hosting)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: cv.topAnchor),
            blur.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            hosting.topAnchor.constraint(equalTo: cv.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
    }

    // MARK: - Show / Hide

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func hideWindow() {
        orderOut(nil)
        saveGeometry()
    }

    func toggleWindow() {
        if isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    // MARK: - Minimize / Expand

    /// Collapse the window to a title-bar-only strip so it can stay floating
    /// during screen sharing without covering content underneath.
    func toggleMinimize() {
        if viewState.isMinimized {
            expandToFullHeight()
        } else {
            collapseToTitleBar()
        }
    }

    private func collapseToTitleBar() {
        savedExpandedHeight = frame.height
        savedExpandedWidth = frame.width
        viewState.isMinimized = true

        // Lock the strip dimensions while minimized — no resize handles.
        minSize = NSSize(width: minimizedWidth, height: minimizedHeight)
        maxSize = NSSize(width: minimizedWidth, height: minimizedHeight)

        // Anchor the top-right corner so the strip lands where the
        // minimize/close cluster already is — no perceived jump.
        var newFrame = frame
        let dh = frame.height - minimizedHeight
        let dw = frame.width - minimizedWidth
        newFrame.size.height = minimizedHeight
        newFrame.size.width = minimizedWidth
        newFrame.origin.y += dh
        newFrame.origin.x += dw
        animateFrame(to: newFrame)
    }

    private func expandToFullHeight() {
        viewState.isMinimized = false

        let targetH = max(savedExpandedHeight, expandedMinHeight)
        let targetW = max(savedExpandedWidth, expandedMinWidth)

        // Restore the normal resize bounds before sizing up, otherwise
        // setFrame clamps to the still-minimized maxSize.
        minSize = NSSize(width: expandedMinWidth, height: expandedMinHeight)
        maxSize = NSSize(width: expandedMaxWidth, height: expandedMaxHeight)

        var newFrame = frame
        let dh = targetH - frame.height
        let dw = targetW - frame.width
        newFrame.size.height = targetH
        newFrame.size.width = targetW
        newFrame.origin.y -= dh
        newFrame.origin.x -= dw
        animateFrame(to: newFrame)
    }

    /// Smooth, consistently-paced resize. NSWindow's built-in `animate: true`
    /// uses `animationResizeTime(for:)` which scales with frame delta — that
    /// reads as sluggish on big jumps. A fixed-duration easeInEaseOut feels
    /// snappier and matches the SwiftUI title-bar animation duration.
    private func animateFrame(to target: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            animator().setFrame(target, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Intercept close — hide instead of destroy.
        hideWindow()
    }

    func windowDidMove(_ notification: Notification) {
        saveGeometry()
    }

    func windowDidResize(_ notification: Notification) {
        saveGeometry()
    }

    // MARK: - Geometry persistence

    private func saveGeometry() {
        // Skip while minimized — the title-bar-only height isn't a height
        // we want to restore on next launch. The pre-minimize height was
        // already persisted by the previous resize.
        if viewState.isMinimized { return }
        let f = frame
        store.windowGeometry = WindowGeometry(
            x: Int(f.origin.x),
            y: Int(f.origin.y),
            w: Int(f.width),
            h: Int(f.height)
        )
        store.save()
    }
}
