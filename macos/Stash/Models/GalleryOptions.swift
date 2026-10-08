import Foundation

enum GalleryLayoutStyle: String, CaseIterable, Identifiable {
    case masonry, rows

    var id: Self { self }

    var title: String {
        switch self {
        case .rows: "Rows"
        case .masonry: "Masonry"
        }
    }
}

enum GallerySortOrder: String, CaseIterable, Identifiable {
    case newestSaved, oldestSaved, newestPosted

    var id: Self { self }

    var title: String {
        switch self {
        case .newestSaved: "Newest Saved"
        case .oldestSaved: "Oldest Saved"
        case .newestPosted: "Newest Posted"
        }
    }

    func areInIncreasingOrder(_ lhs: Bookmark, _ rhs: Bookmark) -> Bool {
        switch self {
        case .newestSaved: lhs.savedAt > rhs.savedAt
        case .oldestSaved: lhs.savedAt < rhs.savedAt
        case .newestPosted: lhs.postedAt > rhs.postedAt
        }
    }
}
