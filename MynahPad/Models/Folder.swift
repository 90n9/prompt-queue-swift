import Foundation

/// A named bucket that groups notes together.
struct Folder: Identifiable, Codable, Equatable {
    var id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }

    /// The default folder every installation starts with.
    static let general = Folder(id: "general", name: "General")
}
