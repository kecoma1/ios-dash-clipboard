import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard") {
                    Label("Add Clipboard in Settings > General > Keyboard > Keyboards > Add New Keyboard.", systemImage: "keyboard")
                    Label("Use the globe key to switch to Clipboard.", systemImage: "globe")
                    Label("Clipboard uses Full Access to save from clipboard, favorite, or delete snippets from the keyboard. Although iOS also permits network access, Clipboard never sends your text or uses network services.", systemImage: "lock")
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .accessibilityIdentifier("settingsOpenSystemSettingsButton")
                }
                Section("Privacy") {
                    Text("Your clipboard stays on your device.")
                    Text("Clipboard has no account, analytics, advertising, or network service. Removing the app removes locally stored snippets.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton") } }
        }
    }
}
