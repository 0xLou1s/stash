import Foundation

enum SidebarItem: Hashable {
    case all
    /// Posts that aren't in any collection yet.
    case inbox
    case trash
    case collection(id: BookmarkCollection.ID)
    case author(handle: String)
}

/// The sidebar in Bookmarks mode.
enum LinkSidebarItem: Hashable {
    /// Folders, then the links that aren't in one (like a browser's bookmarks bar).
    case all
    case trash
    case folder(id: LinkFolder.ID)
    /// Links with this tag, in any folder.
    case tag(String)

    /// Where a link added while this is selected goes.
    var folderID: LinkFolder.ID? {
        if case .folder(let id) = self { id } else { nil }
    }
}
