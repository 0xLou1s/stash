import Foundation

enum SidebarItem: Hashable {
    case all
    /// Posts that aren't in any collection yet.
    case inbox
    case trash
    case collection(id: BookmarkCollection.ID)
    case author(handle: String)
}
