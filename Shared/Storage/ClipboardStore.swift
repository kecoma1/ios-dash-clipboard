import Darwin
import Foundation
import SwiftData

enum ClipboardStoreError: LocalizedError, Equatable {
    case sharedContainerUnavailable
    case readOnly
    case migrationRequiresWriteAccess
    case invalidText
    case corruptData
    case itemNotFound
    case unableToCreateDirectory
    case unableToLock
    case unableToWrite
    case cloudSyncUnavailable

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable: return String(localized: "Shared storage is unavailable.")
        case .readOnly: return String(localized: "Enable Full Access to change saved snippets from the keyboard.")
        case .migrationRequiresWriteAccess: return String(localized: "Open the Clipboard app once to prepare saved snippets.")
        case .invalidText: return String(localized: "Clipboard doesn’t contain text to save.")
        case .corruptData: return String(localized: "Saved snippets can’t be read. Existing data was left unchanged.")
        case .itemNotFound: return String(localized: "That snippet no longer exists.")
        case .unableToCreateDirectory: return String(localized: "Couldn’t prepare shared storage.")
        case .unableToLock: return String(localized: "Couldn’t safely update shared storage.")
        case .unableToWrite: return String(localized: "Couldn’t save the change.")
        case .cloudSyncUnavailable: return String(localized: "Couldn’t start iCloud sync. Your snippets are still on this device.")
        }
    }
}

@Model
final class StoredClipboardItem {
    // CloudKit can't enforce SwiftData uniqueness; new snippets receive random UUIDs.
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date.now
    var isFavorite: Bool = false

    init(item: ClipboardItem) {
        id = item.id
        text = item.text
        createdAt = item.createdAt
        isFavorite = item.isFavorite
    }

    var item: ClipboardItem {
        ClipboardItem(id: id, text: text, createdAt: createdAt, isFavorite: isFavorite)
    }
}

@Model
final class ClipboardStoreMetadata {
    var key: String = ""
    var value: String = ""

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// A SwiftData store shared by the app and keyboard. A context is created for each operation and
/// only value-type DTOs leave it. Writers use an advisory process lock around fetch/mutate/save,
/// which preserves the consecutive-deduplication invariant across the app and extension.
final class ClipboardStore: @unchecked Sendable {
    enum Access { case readOnly, readWrite }
    private enum LegacyMigrationState: String { case imported, verified }

    private static let legacyMigrationKey = "legacy-json-v1-imported"

    private let containerURL: URL
    private let access: Access
    private let fileManager: FileManager
    private let notificationCenter: CFNotificationCenter
    private var cloudSyncEnabled: Bool
    // Keep the mirroring container alive so imports and exports can run after a user action ends.
    // The app accesses this state on its serial storage queue; the keyboard always uses .none.
    private var cloudContainer: ModelContainer?

    init(
        containerURL: URL,
        access: Access,
        cloudSyncEnabled: Bool = false,
        fileManager: FileManager = .default,
        notificationCenter: CFNotificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    ) {
        self.containerURL = containerURL
        self.access = access
        self.fileManager = fileManager
        self.notificationCenter = notificationCenter
        self.cloudSyncEnabled = cloudSyncEnabled && access == .readWrite
    }

    convenience init(access: Access, cloudSyncEnabled: Bool = false) throws {
        try self.init(containerURL: AppGroup.containerURL(), access: access, cloudSyncEnabled: cloudSyncEnabled)
    }

    private var databaseURL: URL { containerURL.appendingPathComponent(AppGroup.swiftDataStoreFilename) }
    private var legacyDataURL: URL { containerURL.appendingPathComponent(AppGroup.storeFilename) }
    private var lockURL: URL { containerURL.appendingPathComponent(AppGroup.writerLockFilename) }

    /// Called by the containing app on the same serial queue as its storage operations.
    /// A failed enable leaves the local configuration active and the preference unchanged.
    func setCloudSyncEnabled(_ enabled: Bool) throws {
        guard access == .readWrite else { throw ClipboardStoreError.readOnly }
        guard enabled != cloudSyncEnabled else { return }
        if enabled {
            try withWriterLock {
                // Finish the previous JSON import before CloudKit can import another device's
                // migration marker into this shared store.
                try migrateLegacyIfNeeded(lockHeld: true)
                cloudSyncEnabled = true
                do { _ = try makeContainer(allowsSave: true) }
                catch {
                    cloudContainer = nil
                    cloudSyncEnabled = false
                    throw error
                }
            }
        } else {
            cloudContainer = nil
            cloudSyncEnabled = false
        }
    }

    func load() throws -> [ClipboardItem] {
        if access == .readWrite {
            try withWriterLock { try migrateLegacyIfNeeded(lockHeld: true) }
        } else if !fileManager.fileExists(atPath: databaseURL.path) {
            // A reader never initializes SwiftData because that can create a new SQLite store.
            if fileManager.fileExists(atPath: legacyDataURL.path) { throw ClipboardStoreError.migrationRequiresWriteAccess }
            return []
        } else if fileManager.fileExists(atPath: legacyDataURL.path), try migrationStateInExistingStore() != .verified {
            // A failed pre-SwiftData migration may have created an empty SQLite file. Do not
            // present that file as an empty clipboard while its legacy archive is unresolved.
            throw ClipboardStoreError.migrationRequiresWriteAccess
        }
        return try fetchItems(allowsSave: false)
    }

    @discardableResult
    func add(text: String, now: Date = .now) throws -> ClipboardItem {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipboardStoreError.invalidText
        }
        return try mutate { context, current in
            // Only consecutive duplicates collapse. Reusing an older snippet is intentional.
            if let newest = current.map(\.item).newestFirst().first, newest.text == text { return newest }
            let item = ClipboardItem(text: text, createdAt: now)
            context.insert(StoredClipboardItem(item: item))
            return item
        }
    }

    func update(id: UUID, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipboardStoreError.invalidText
        }
        _ = try mutate { _, current in
            guard let model = current.first(where: { $0.id == id }) else { throw ClipboardStoreError.itemNotFound }
            model.text = text
            return ()
        }
    }

    func toggleFavorite(id: UUID) throws {
        _ = try mutate { _, current in
            guard let model = current.first(where: { $0.id == id }) else { throw ClipboardStoreError.itemNotFound }
            model.isFavorite.toggle()
            return ()
        }
    }

    func delete(id: UUID) throws {
        _ = try mutate { context, current in
            guard let model = current.first(where: { $0.id == id }) else { throw ClipboardStoreError.itemNotFound }
            context.delete(model)
            return ()
        }
    }

    private func mutate<T>(_ operation: (ModelContext, [StoredClipboardItem]) throws -> T) throws -> T {
        guard access == .readWrite else { throw ClipboardStoreError.readOnly }
        return try withWriterLock {
            try migrateLegacyIfNeeded(lockHeld: true)
            let container = try makeContainer(allowsSave: true)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let current = try fetchModels(in: context)
            let result = try operation(context, current)
            do { try context.save() }
            catch { throw ClipboardStoreError.unableToWrite }
            try finalizeStorageAttributes()
            CFNotificationCenterPostNotification(
                notificationCenter,
                CFNotificationName(AppGroup.changeNotification as CFString),
                nil,
                nil,
                true
            )
            return result
        }
    }

    /// Imports the legacy JSON archive in two durable states. `imported` is committed with every
    /// item, then a separate read-only context verifies the save before the state becomes
    /// `verified` and the archive can be removed. A crash at either boundary cannot re-import.
    private func migrateLegacyIfNeeded(lockHeld: Bool) throws {
        precondition(lockHeld)
        guard access == .readWrite else { throw ClipboardStoreError.migrationRequiresWriteAccess }

        let databaseExists = fileManager.fileExists(atPath: databaseURL.path)
        let legacyItems: [ClipboardItem]
        if databaseExists {
            legacyItems = []
        } else {
            // Validate the archive before SwiftData creates its first SQLite file.
            legacyItems = try decodeAndValidateLegacyItems()
        }

        let container = try makeContainer(allowsSave: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        switch try migrationState(in: context) {
        case .verified:
            try finalizeStorageAttributes()
            try removeLegacyArchiveAfterVerifiedMigration()
            return
        case .imported:
            // The previous save was atomic. Re-read the SwiftData store before advancing the
            // durable marker, without parsing a possibly stale/corrupt residual JSON archive.
            _ = try fetchItems(allowsSave: false)
            try setMigrationState(.verified, in: context)
            try finalizeStorageAttributes()
            try removeLegacyArchiveAfterVerifiedMigration()
            return
        case nil:
            break
        }

        // A database without a marker is only acceptable when it accompanies a validated
        // legacy archive. An empty store can result if initialization was interrupted before
        // its first marker save; finish that initialization. Rows without a marker are unsafe.
        if databaseExists, !fileManager.fileExists(atPath: legacyDataURL.path) {
            guard try fetchModels(in: context).isEmpty else { throw ClipboardStoreError.corruptData }
        }
        let itemsToImport = databaseExists ? try decodeAndValidateLegacyItems() : legacyItems

        for item in itemsToImport { context.insert(StoredClipboardItem(item: item)) }
        context.insert(ClipboardStoreMetadata(key: Self.legacyMigrationKey, value: LegacyMigrationState.imported.rawValue))
        do { try context.save() }
        catch { throw ClipboardStoreError.unableToWrite }

        // Do not delete the legacy archive until a separate, read-only context can read the
        // exact values saved above. No persistent model leaves either context.
        let verified = try fetchItems(allowsSave: false)
        guard verified.newestFirst() == itemsToImport.newestFirst() else { throw ClipboardStoreError.unableToWrite }
        try setMigrationState(.verified, in: context)
        try finalizeStorageAttributes()
        try removeLegacyArchiveAfterVerifiedMigration()
    }

    private func migrationState(in context: ModelContext) throws -> LegacyMigrationState? {
        let metadata = try context.fetch(FetchDescriptor<ClipboardStoreMetadata>())
        return metadata.first(where: { $0.key == Self.legacyMigrationKey })
            .flatMap { LegacyMigrationState(rawValue: $0.value) }
    }

    private func setMigrationState(_ state: LegacyMigrationState, in context: ModelContext) throws {
        guard let metadata = try context.fetch(FetchDescriptor<ClipboardStoreMetadata>()).first(where: { $0.key == Self.legacyMigrationKey }) else {
            throw ClipboardStoreError.unableToWrite
        }
        metadata.value = state.rawValue
        do { try context.save() }
        catch { throw ClipboardStoreError.unableToWrite }
    }

    private func migrationStateInExistingStore() throws -> LegacyMigrationState? {
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try migrationState(in: context)
    }

    private func decodeAndValidateLegacyItems() throws -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: legacyDataURL.path) else { return [] }
        do {
            let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: legacyDataURL))
            guard Set(items.map(\.id)).count == items.count else { throw ClipboardStoreError.corruptData }
            return items
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.corruptData
        }
    }

    private func fetchItems(allowsSave: Bool) throws -> [ClipboardItem] {
        let container = try makeContainer(allowsSave: allowsSave)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try fetchModels(in: context).map(\.item).newestFirst()
    }

    private func fetchModels(in context: ModelContext) throws -> [StoredClipboardItem] {
        do { return try context.fetch(FetchDescriptor<StoredClipboardItem>()) }
        catch { throw ClipboardStoreError.unableToWrite }
    }

    private func makeContainer(allowsSave: Bool) throws -> ModelContainer {
        if allowsSave {
            do { try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true) }
            catch { throw ClipboardStoreError.unableToCreateDirectory }
        }
        let schema = Schema([StoredClipboardItem.self, ClipboardStoreMetadata.self])
        if cloudSyncEnabled, access == .readWrite, let cloudContainer { return cloudContainer }
        let configuration = ModelConfiguration(
            "Clipboard",
            schema: schema,
            url: databaseURL,
            allowsSave: cloudSyncEnabled ? true : allowsSave,
            cloudKitDatabase: cloudSyncEnabled ? .private(AppGroup.cloudKitContainerIdentifier) : .none
        )
        if fileManager.fileExists(atPath: databaseURL.path) { try validateSQLiteHeader() }
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            if cloudSyncEnabled { cloudContainer = container }
            return container
        }
        catch {
            if cloudSyncEnabled { throw ClipboardStoreError.cloudSyncUnavailable }
            throw fileManager.fileExists(atPath: databaseURL.path)
                ? ClipboardStoreError.corruptData
                : ClipboardStoreError.sharedContainerUnavailable
        }
    }

    private func validateSQLiteHeader() throws {
        do {
            let header = try Data(contentsOf: databaseURL, options: [.mappedIfSafe]).prefix(16)
            guard header == Data("SQLite format 3\0".utf8) else { throw ClipboardStoreError.corruptData }
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.corruptData
        }
    }

    private func prepareSharedStorageDirectory() throws {
        do { try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true) }
        catch { throw ClipboardStoreError.unableToCreateDirectory }
        var directory = containerURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try directory.setResourceValues(values)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
        }
        catch { throw ClipboardStoreError.unableToWrite }
    }

    private func finalizeStorageAttributes() throws {
        try prepareSharedStorageDirectory()
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: databaseURL.path
            )
        } catch {
            throw ClipboardStoreError.unableToWrite
        }
    }

    private func removeLegacyArchiveAfterVerifiedMigration() throws {
        guard fileManager.fileExists(atPath: legacyDataURL.path) else { return }
        do { try fileManager.removeItem(at: legacyDataURL) }
        catch { throw ClipboardStoreError.unableToWrite }
    }

    private func withWriterLock<T>(_ body: () throws -> T) throws -> T {
        guard access == .readWrite else { throw ClipboardStoreError.readOnly }
        try prepareSharedStorageDirectory()
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ClipboardStoreError.unableToLock }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw ClipboardStoreError.unableToLock }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
