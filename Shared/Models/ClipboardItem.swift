import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var text: String
    let createdAt: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}

extension Array where Element == ClipboardItem {
    /// Most recent first; UUID makes equal timestamps deterministic.
    func newestFirst() -> [ClipboardItem] {
        sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
