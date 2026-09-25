import SwiftUI
#if DEBUG
import CoreData
import SwiftData
import _SwiftData_CoreData
#endif

@main
struct IOSClipboardApp: App {
    @StateObject private var model = ClipboardAppModel()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
            do { try Self.initializeDevelopmentCloudKitSchema() }
            catch { fatalError("CloudKit schema initialization failed: \(error)") }
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestDisableICloudSync") {
            UserDefaults.standard.removeObject(forKey: AppGroup.cloudSyncPreferenceKey)
        }
        #endif
    }

    #if DEBUG
    /// One-time developer action. Uses a disposable store so it never opens a user's snippets
    /// with Core Data and SwiftData at the same time.
    private static func initializeDevelopmentCloudKitSchema() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-cloudkit-schema-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(
                for: [StoredClipboardItem.self, ClipboardStoreMetadata.self]
            ) else {
                throw ClipboardStoreError.cloudSyncUnavailable
            }
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: AppGroup.cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "Clipboard", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ClipboardListView(model: model)
                .task { model.reload() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    model.reload()
                }
        }
    }
}
