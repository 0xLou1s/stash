import SwiftUI

/// A sidebar row that turns into a text field while being renamed.
struct RenamableRow: View {
    let name: String
    let systemImage: String
    let count: Int
    @Binding var isRenaming: Bool
    /// Called with the trimmed new name, only when it changed.
    let rename: (String) -> Void

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        if isRenaming {
            Label {
                TextField("Name", text: $draft)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onExitCommand { isRenaming = false }
            } icon: {
                Image(systemName: systemImage)
            }
            .task {
                draft = name
                isEditing = true
            }
            .onChange(of: isEditing) {
                if !isEditing { commit() }
            }
        } else {
            Label(name, systemImage: systemImage)
                .badge(count)
        }
    }

    private func commit() {
        guard isRenaming else { return }
        isRenaming = false

        let newName = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != name else { return }
        rename(newName)
    }
}
