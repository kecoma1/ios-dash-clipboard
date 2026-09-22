import Foundation

enum AppGroup {
    static let identifier = "group.com.iosdashclipboard.shared"
    /// JSON written by versions prior to the SwiftData migration. It is never the active store.
    static let storeFilename = "clipboard-items-v1.json"
    static let swiftDataStoreFilename = "clipboard-items.store"
    static let writerLockFilename = ".clipboard-items.lock"
    static let changeNotification = "com.iosdashclipboard.items-changed"

    static func containerURL(fileManager: FileManager = .default) throws -> URL {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw ClipboardStoreError.sharedContainerUnavailable
        }
        return url
    }
}
