import Foundation
import Testing
@testable import Stash

@Suite("Reading Chrome's bookmarks")
struct ChromeBookmarksTests {
    let library = TemporaryLibrary()

    private let file = """
    { "checksum": "x", "version": 1, "roots": {
      "bookmark_bar": { "id": "1", "type": "folder", "name": "Bookmarks bar", "children": [
        { "id": "10", "type": "folder", "name": "UI Libraries", "children": [
          { "id": "11", "type": "url", "name": "Aceternity UI", "url": "https://ui.aceternity.com/", "date_added": "13400000000000000" },
          { "id": "12", "type": "folder", "name": "Animation", "children": [
            { "id": "13", "type": "url", "name": "Motion", "url": "https://motion.dev/" }
          ] },
          { "id": "14", "type": "folder", "name": "Empty", "children": [] }
        ] },
        { "id": "20", "type": "url", "name": "Bookmarklet", "url": "javascript:alert(1)" },
        { "id": "21", "type": "url", "name": "Settings", "url": "chrome://settings" }
      ] },
      "other": { "id": "2", "type": "folder", "name": "Other bookmarks", "children": [] },
      "synced": { "id": "3", "type": "folder", "name": "Mobile bookmarks", "children": [
        { "id": "30", "type": "url", "name": "Jotai", "url": "https://jotai.org/" }
      ] }
    } }
    """

    @Test func `reads folders with their web pages, skipping empty folders and browser links`() throws {
        let roots = try ChromeBookmarks.folders(in: Data(file.utf8))

        #expect(roots.map(\.name) == ["Bookmarks bar", "Mobile bookmarks"])
        let bar = try #require(roots.first)
        #expect(bar.pages.isEmpty, "bookmarklet and chrome:// skipped")
        let ui = try #require(bar.subfolders.first)
        #expect(ui.name == "UI Libraries")
        #expect(ui.subfolders.map(\.name) == ["Animation"])
        #expect(ui.pageCount == 2)
        #expect(ui.allPages.map(\.title) == ["Aceternity UI", "Motion"])
    }

    @Test func `converts Chrome's timestamps`() throws {
        let page = try #require(ChromeBookmarks.folders(in: Data(file.utf8)).first?.allPages.first)
        // 13400000000000000 µs since 1601 = 1755526400 s since 1970.
        #expect(page.addedAt == Date(timeIntervalSince1970: 1_755_526_400))
    }

    @Test func `lists profiles that have bookmarks, by their Chrome names`() throws {
        let chrome = library.folder.appending(path: "Chrome")
        for profile in ["Default", "Profile 2", "System Profile"] {
            try FileManager.default.createDirectory(at: chrome.appending(path: profile), withIntermediateDirectories: true)
        }
        try Data(file.utf8).write(to: chrome.appending(path: "Default/Bookmarks"))
        try Data(file.utf8).write(to: chrome.appending(path: "Profile 2/Bookmarks"))
        try Data(#"{ "profile": { "info_cache": { "Default": { "name": "Work" }, "Profile 2": { "name": "Personal" } } } }"#.utf8)
            .write(to: chrome.appending(path: "Local State"))

        let profiles = ChromeBookmarks.profiles(in: chrome)

        #expect(profiles.map(\.name) == ["Personal", "Work"])
        #expect(profiles.map(\.id) == ["Profile 2", "Default"])
    }

    @Test func `imports into a folder by name, skipping pages already saved`() async throws {
        let store = LinkStore(service: library.service()) { _ in LinkMetadata(title: "Fetched", iconURL: URL(string: "https://icon.dev/i.png")) }
        await store.load()
        await store.add(URL(string: "https://motion.dev/")!, title: "Already here")
        let pages = try #require(ChromeBookmarks.folders(in: Data(file.utf8)).first?.subfolders.first).allPages

        let added = await store.importPages(pages, intoFolderNamed: "UI Libraries")
        let again = await store.importPages(pages, intoFolderNamed: "UI Libraries")

        #expect(added.map(\.title) == ["Aceternity UI"])
        #expect(again.isEmpty)
        #expect(store.folders.map(\.name) == ["UI Libraries"], "reused, not duplicated")
        #expect(store.links.count == 2)
        #expect(store.links.first { $0.title == "Already here" }?.folderID == nil, "left where it was")
        #expect(added.first?.savedAt == Date(timeIntervalSince1970: 1_755_526_400), "keeps Chrome's date")
        #expect(try await library.service().fetchLinks().count == 2, "persisted")
    }

    @Test func `loads icons for imported links and keeps their titles`() async throws {
        let icon = URL(string: "https://icon.dev/i.png")!
        let store = LinkStore(service: library.service()) { _ in LinkMetadata(title: "Fetched", iconURL: icon) }
        await store.load()
        let pages = (0..<30).map { ImportedPage(title: "Page \($0)", url: URL(string: "https://site\($0).dev")!) }
        let added = await store.importPages(pages, intoFolderNamed: "Lots")

        await store.refreshMetadata(of: added.map(\.id), keepingTitles: true)

        #expect(store.links.allSatisfy { $0.iconURL == icon })
        #expect(store.links.allSatisfy { $0.title.hasPrefix("Page ") })
        #expect(try await library.service().fetchLinks().allSatisfy { $0.iconURL == icon }, "persisted")
    }
}
