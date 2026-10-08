import SwiftUI

@main
struct StashApp: App {
    @State private var store: BookmarkStore
    @State private var bridge: ExtensionBridge
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        // AsyncImage loads through the shared URL cache, whose defaults are tiny.
        // A bigger one keeps gallery images from re-downloading and flashing
        // their placeholders as you scroll or switch views.
        URLCache.shared = URLCache(memoryCapacity: 128 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024)

        let store = BookmarkStore(service: LocalBookmarkService())
        _store = State(initialValue: store)
        _bridge = State(initialValue: ExtensionBridge(store: store))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .task {
                    await store.load()
                    // Only after loading, so posts from the extension merge with what's on disk.
                    bridge.start()
                }
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
