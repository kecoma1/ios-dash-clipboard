import Foundation
import Combine

@MainActor
final class ClipboardAppModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var errorMessage: String?

    private let store: ClipboardStore?
    private let ioQueue = DispatchQueue(label: "com.iosdashclipboard.storage", qos: .userInitiated)

    init(store: ClipboardStore? = try? ClipboardStore(access: .readWrite)) {
        self.store = store
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
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(AppGroup.changeNotification as CFString), nil)
    }

    func reload() {
        guard let store else { return }
        ioQueue.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                switch result {
                case let .success(items): self?.items = items
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
