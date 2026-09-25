import Foundation
import Combine
import CoreData

@MainActor
final class ClipboardAppModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var errorMessage: String?
    @Published private(set) var isCloudSyncEnabled: Bool
    @Published private(set) var isChangingCloudSync = false
    @Published var cloudSyncErrorMessage: String?

    private let store: ClipboardStore?
    private let ioQueue = DispatchQueue(label: "com.iosclipboard.storage", qos: .userInitiated)
    private var cloudEventObserver: NSObjectProtocol?

    init(store: ClipboardStore? = try? ClipboardStore(
        access: .readWrite,
        cloudSyncEnabled: UserDefaults.standard.bool(forKey: AppGroup.cloudSyncPreferenceKey)
    )) {
        self.store = store
        isCloudSyncEnabled = UserDefaults.standard.bool(forKey: AppGroup.cloudSyncPreferenceKey)
        if store == nil { errorMessage = ClipboardStoreError.sharedContainerUnavailable.localizedDescription }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let model = Unmanaged<ClipboardAppModel>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { model.reload() }
            },
            AppGroup.changeNotification as CFString, nil, .deliverImmediately)
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let imported = event.type == .import && event.succeeded
            let failed = !event.succeeded
            Task { @MainActor [weak self] in
                guard let self, self.isCloudSyncEnabled else { return }
                if imported {
                    self.reload()
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        CFNotificationName(AppGroup.changeNotification as CFString),
                        nil, nil, true
                    )
                } else if failed {
                    self.cloudSyncErrorMessage = String(localized: "iCloud couldn’t sync right now. Your snippets remain available on this device.")
                }
            }
        }
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(AppGroup.changeNotification as CFString), nil)
        if let cloudEventObserver { NotificationCenter.default.removeObserver(cloudEventObserver) }
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        guard !isChangingCloudSync, enabled != isCloudSyncEnabled else { return }
        guard let store else {
            cloudSyncErrorMessage = ClipboardStoreError.sharedContainerUnavailable.localizedDescription
            return
        }
        isChangingCloudSync = true
        ioQueue.async { [weak self] in
            let result = Result { try store.setCloudSyncEnabled(enabled) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChangingCloudSync = false
                switch result {
                case .success:
                    UserDefaults.standard.set(enabled, forKey: AppGroup.cloudSyncPreferenceKey)
                    self.isCloudSyncEnabled = enabled
                    self.cloudSyncErrorMessage = nil
                    self.reload()
                case let .failure(error):
                    self.cloudSyncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func reload() {
        guard let store else { return }
        ioQueue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                switch result {
                case let .success(items): self?.items = items; self?.errorMessage = nil
                case let .failure(error): self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func add(_ text: String, completion: @escaping (Bool) -> Void = { _ in }) {
        perform({ try $0.add(text: text) }, completion: completion)
    }

    func update(_ item: ClipboardItem, text: String, completion: @escaping (Bool) -> Void = { _ in }) {
        perform({ try $0.update(id: item.id, text: text) }, completion: completion)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        perform { try $0.toggleFavorite(id: item.id) }
    }

    func delete(_ item: ClipboardItem) {
        perform { try $0.delete(id: item.id) }
    }

    private func perform(_ action: @escaping (ClipboardStore) throws -> Void, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let store else {
            errorMessage = ClipboardStoreError.sharedContainerUnavailable.localizedDescription
            completion(false)
            return
        }
        ioQueue.async { [weak self] in
            let result = Result { try action(store); return try store.load() }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(items): self.items = items; self.errorMessage = nil; completion(true)
                case let .failure(error): self.errorMessage = error.localizedDescription; completion(false)
                }
            }
        }
    }
}
