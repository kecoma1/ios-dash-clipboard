import SwiftUI

struct SnippetEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: ClipboardItem
    @ObservedObject var model: ClipboardAppModel
    @State private var text: String
    @State private var showingDiscardConfirmation = false
    @State private var saveError: String?

    init(item: ClipboardItem, model: ClipboardAppModel) {
        self.item = item
        self.model = model
        _text = State(initialValue: item.text)
    }

    var body: some View {
        TextEditor(text: $text)
            .padding(8)
            .navigationTitle("Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if text == item.text { dismiss() } else { showingDiscardConfirmation = true }
                    }
                    .accessibilityIdentifier("snippetEditorCancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.update(item, text: text) { if $0 { dismiss() } else { saveError = model.errorMessage ?? String(localized: "Couldn’t save this snippet.") } }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == item.text)
                    .accessibilityIdentifier("snippetEditorSaveButton")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showingDiscardConfirmation) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .alert("Couldn’t Save Snippet", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK", role: .cancel) { saveError = nil } } message: { Text(saveError ?? "") }
    }
}
