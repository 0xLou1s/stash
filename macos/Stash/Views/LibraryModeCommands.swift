import SwiftUI

extension FocusedValues {
    /// The focused window's mode, so the View menu can switch it.
    @Entry var libraryMode: Binding<LibraryMode>?
}

/// View menu items that switch the focused window's mode.
struct LibraryModeCommands: Commands {
    @FocusedBinding(\.libraryMode) private var mode

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(LibraryMode.allCases) { option in
                Toggle(option.title, isOn: Binding(
                    get: { mode == option },
                    set: { if $0 { mode = option } }
                ))
                .keyboardShortcut(option.shortcut)
                .disabled(mode == nil)
            }
            Divider()
        }
    }
}
