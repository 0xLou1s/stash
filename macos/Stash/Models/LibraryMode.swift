import SwiftUI

/// The two halves of the library, switched from the toolbar. Each has its own sidebar.
enum LibraryMode: String, CaseIterable, Identifiable {
    /// Posts saved from X.
    case inspire
    /// Web pages.
    case bookmarks

    var id: Self { self }

    var title: String {
        switch self {
        case .inspire: "Inspire"
        case .bookmarks: "Bookmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .inspire: "sparkles"
        case .bookmarks: "bookmark"
        }
    }

    /// ⌘1, ⌘2, in the View menu.
    var shortcut: KeyEquivalent {
        switch self {
        case .inspire: "1"
        case .bookmarks: "2"
        }
    }
}
