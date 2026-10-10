import Foundation
import Testing
@testable import Stash

@Suite("LinkStore")
struct LinkStoreTests {
    let library = TemporaryLibrary()
    let page = URL(string: "https://ui.aceternity.com")!

    private func store(metadata: LinkMetadata? = nil) async -> LinkStore {
        let store = LinkStore(service: library.service()) { _ in metadata }
        await store.load()
        return store
    }

    @Test func `saves a page with its title and icon from the web`() async throws {
        let icon = URL(string: "https://ui.aceternity.com/favicon.png")!
        let store = await store(metadata: LinkMetadata(title: "Aceternity UI", iconURL: icon))

        await store.add(page)

        let link = try #require(store.links.first)
        #expect(link.title == "Aceternity UI")
        #expect(link.iconURL == icon)
        #expect(try await library.service().fetchLinks().map(\.title) == ["Aceternity UI"], "persisted")
    }

    @Test func `keeps a name given when saving`() async throws {
        let store = await store(metadata: LinkMetadata(title: "From the page"))

        await store.add(page, title: "Mine")

        #expect(store.links.map(\.title) == ["Mine"])
    }

    @Test func `names a page by its host when the web has nothing`() async throws {
        let store = await store(metadata: nil)

        await store.add(URL(string: "https://www.example.com/a")!)

        #expect(store.links.map(\.title) == ["example.com"])
    }

    @Test func `saving a page again moves it instead of duplicating it`() async throws {
        let store = await store()
        let folder = try #require(await store.createFolder())
        await store.add(page)
        await store.moveToTrash(Set(store.links.map(\.id)))

        await store.add(page, to: folder.id)

        #expect(store.links.count == 1)
        #expect(store.links.first?.folderID == folder.id)
        #expect(store.links.first?.isTrashed == false, "back from Trash")
    }

    @Test func `all lists links outside folders, but search looks in folders too`() async throws {
        let store = await store()
        let folder = try #require(await store.createFolder())
        await store.add(URL(string: "https://loose.dev")!)
        await store.add(URL(string: "https://filed.dev")!, to: folder.id)

        #expect(store.links(in: .all, matching: "").map(\.url.displayHost) == ["loose.dev"])
        #expect(store.links(in: .folder(id: folder.id), matching: "").map(\.url.displayHost) == ["filed.dev"])
        #expect(store.links(in: .all, matching: "filed").map(\.url.displayHost) == ["filed.dev"])
        #expect(store.sidebarCounts[.all] == 2)
        #expect(store.sidebarCounts[.folder(id: folder.id)] == 1)
    }

    @Test func `deleting a folder keeps its links, outside any folder`() async throws {
        let store = await store()
        let folder = try #require(await store.createFolder())
        await store.add(page, to: folder.id)

        await store.deleteFolder(folder.id)

        #expect(store.folders.isEmpty)
        #expect(store.links(in: .all, matching: "").map(\.url) == [page])
        let relaunched = await self.store()
        #expect(relaunched.links.first?.folderID == nil, "persisted")
    }

    @Test func `trash, put back, and delete for good`() async throws {
        let store = await store()
        let link = try #require(await store.add(page))

        await store.moveToTrash([link.id])
        #expect(store.links(in: .trash, matching: "").count == 1)
        #expect(store.links(in: .all, matching: "").isEmpty)

        await store.putBack([link.id])
        #expect(store.links(in: .all, matching: "").count == 1)

        await store.moveToTrash([link.id])
        await store.emptyTrash()
        #expect(store.links.isEmpty)
        #expect(try await library.service().fetchLinks().isEmpty)
    }

    @Test func `editing the address loads the new page's icon`() async throws {
        let icon = URL(string: "https://other.dev/icon.png")!
        let store = await store(metadata: LinkMetadata(title: "Other", iconURL: icon))
        let link = try #require(await store.add(page, title: "Kept"))

        await store.edit(link.id, url: URL(string: "https://other.dev")!, title: "Kept", folderID: nil)

        #expect(store.link(id: link.id)?.iconURL == icon)
        #expect(store.link(id: link.id)?.title == "Kept")
    }
}

@Suite("LinkStore tags")
struct LinkStoreTagTests {
    let library = TemporaryLibrary()

    @Test func `tags are tidied, filterable, counted, and searchable`() async throws {
        let store = LinkStore(service: library.service()) { _ in nil }
        await store.load()
        let folder = try #require(await store.createFolder())
        let shadcn = try #require(await store.add(URL(string: "https://ui.shadcn.com")!, to: folder.id, tags: [" Shadcn", "react", "react", ""]))
        await store.add(URL(string: "https://motion.dev")!, tags: ["react"])

        #expect(store.link(id: shadcn.id)?.tags == ["react", "shadcn"])
        #expect(store.tags == ["react", "shadcn"])
        #expect(store.links(in: .tag("react"), matching: "").count == 2, "across folders")
        #expect(store.sidebarCounts[.tag("shadcn")] == 1)
        #expect(store.links(in: .all, matching: "shad").map(\.id) == [shadcn.id])
    }

    @Test func `adding and removing a tag`() async throws {
        let store = LinkStore(service: library.service()) { _ in nil }
        await store.load()
        let link = try #require(await store.add(URL(string: "https://gsap.com")!))

        await store.setTag("js", included: true, for: [link.id])
        #expect(store.link(id: link.id)?.tags == ["js"])

        await store.removeTag("js")
        #expect(store.tags.isEmpty)
        #expect(try await library.service().fetchLinks().first?.tags == [], "persisted")
    }

    @Test func `reads links saved before tags existed`() throws {
        let json = #"{ "id": "1", "url": "https://gsap.com", "title": "GSAP", "savedAt": "2026-01-01T00:00:00Z" }"#
        let link = try StashJSON.decoder.decode(SavedLink.self, from: Data(json.utf8))
        #expect(link.tags.isEmpty)
    }
}
