import SwiftUI

@main
struct IOSDashClipboardApp: App {
    @StateObject private var model = ClipboardAppModel()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        #endif
    }

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
