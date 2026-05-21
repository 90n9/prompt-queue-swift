import Foundation

/// A single text prompt managed by MynahPad.
/// `id`, `folder_id`, and `created_at` use snake_case keys to match the
/// cross-app JSON schema produced by the Python version.
struct Note: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var folder_id: String
    var used: Bool
    var created_at: Double  // Unix timestamp (seconds)

    init(id: String = UUID().uuidString,
         text: String,
         folder_id: String = "general",
         used: Bool = false,
         created_at: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.text = text
        self.folder_id = folder_id
        self.used = used
        self.created_at = created_at
    }
}
