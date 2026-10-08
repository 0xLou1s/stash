import SwiftUI

@main
struct StashApp: App {
    @State private var store = BookmarkStore(service: MockBookmarkService())
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .task { await store.load() }
                .onChange(of: appearance, initial: true) {
                    NSApp.appearance = appearance.nsAppearance
                }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await store.load() }
                }
                .keyboardShortcut("r")
            }
            CommandGroup(before: .sidebar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Divider()
            }
        }

        Settings {
            SettingsView()
        }
    }
}
