import Foundation
import Testing
@testable import Stash

@Suite("Bookmark list rows")
struct LinkListEntryTests {
    private func entry(_ title: String, _ address: String, tags: [String] = []) -> LinkListEntry {
        var link = SavedLink(url: URL(string: address)!, title: title)
        link.tags = tags
        return LinkListEntry(link: link)
    }

    @Test func `sorts by a column in natural order, either way`() {
        let entries = [entry("Item 10", "https://b.dev"), entry("item 2", "https://c.dev"), entry("Item 1", "https://a.dev")]

        #expect(entries.sorted(by: LinkSort(column: .name).areInIncreasingOrder).map(\.name) == ["Item 1", "item 2", "Item 10"])
        #expect(entries.sorted(by: LinkSort(column: .site, ascending: false).areInIncreasingOrder).map(\.site) == ["c.dev", "b.dev", "a.dev"])
    }

    @Test func `a link shows its domain and tags; a folder its count`() {
        let link = entry("GSAP", "https://www.gsap.com/docs", tags: ["js", "library"])
        let folder = LinkListEntry(folder: LinkFolder(name: "Animation"), count: 3)

        #expect(link.site == "gsap.com")
        #expect(link.sortKey(for: .tags) == "js, library")
        #expect(link.help == "GSAP\nhttps://www.gsap.com/docs\njs, library")
        #expect(!link.isFolder)
        #expect(folder.isFolder && folder.count == 3)
    }
}
