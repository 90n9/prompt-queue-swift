import Foundation
import Combine

/// Bridge between Sparkle's delegate callbacks (in AppDelegate) and the
/// SwiftUI panel. AppDelegate writes; NoteListView observes and renders a
/// banner with an "Update Now" button that re-presents the native install
/// dialog without forcing the user to dig through the menu bar.
final class UpdateNotifier: ObservableObject {
    static let shared = UpdateNotifier()

    @Published var availableVersion: String?

    var onInstallTapped: (() -> Void)?

    private init() {}

    func setAvailable(version: String?) {
        if Thread.isMainThread {
            availableVersion = version
        } else {
            DispatchQueue.main.async { self.availableVersion = version }
        }
    }

    func dismiss() {
        setAvailable(version: nil)
    }
}
