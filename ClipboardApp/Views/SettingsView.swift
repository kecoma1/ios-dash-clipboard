import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var model: ClipboardAppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { model.isCloudSyncEnabled },
                        set: { model.setCloudSyncEnabled($0) }
                    ))
                    .disabled(model.isChangingCloudSync)
                    .accessibilityIdentifier("settingsICloudSyncToggle")
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Optional. Sync saved snippets across your devices signed in to the same Apple Account. Turning this off keeps snippets on this device and stops future syncing; copies already in iCloud remain there.")
                }
                Section("Keyboard") {
                    Label("Add Clipboard in Settings > General > Keyboard > Keyboards > Add New Keyboard.", systemImage: "keyboard")
                    Label("Use the globe key to switch to Clipboard.", systemImage: "globe")
                    Label("Clipboard uses Full Access to save from clipboard, favorite, or delete snippets from the keyboard. The keyboard itself does not connect to iCloud.", systemImage: "lock")
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .accessibilityIdentifier("settingsOpenSystemSettingsButton")
                }
                Section("Privacy") {
                    Text("Snippets stay on this device unless you turn on iCloud sync.")
                    Text("Clipboard has no app account, analytics, or advertising. If iCloud sync is on, saved snippets are stored in your private iCloud database.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton") } }
            .alert("iCloud Sync", isPresented: Binding(
                get: { model.cloudSyncErrorMessage != nil },
                set: { if !$0 { model.cloudSyncErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.cloudSyncErrorMessage = nil }
            } message: { Text(model.cloudSyncErrorMessage ?? "") }
        }
    }
}
