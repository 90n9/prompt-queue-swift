import SwiftUI

/// Entry point. We use the AppDelegate lifecycle so we have full control over
/// NSStatusItem, the floating window, and activation policy. SwiftUI's scene
/// machinery is present only to satisfy the @main contract; the actual UI is
/// driven by AppDelegate.
@main
struct MynahPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // An empty Settings scene prevents SwiftUI from auto-creating a window.
        // Our window is managed entirely by NoteListWindow / AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
