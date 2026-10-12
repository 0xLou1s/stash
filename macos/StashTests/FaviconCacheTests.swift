import AppKit
import Foundation
import Testing
@testable import Stash

@Suite("FaviconCache")
struct FaviconCacheTests {
    let library = TemporaryLibrary()

    /// A 2×2 PNG at a file URL, standing in for a site's icon.
    private func iconFile() throws -> URL {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let url = library.folder.appending(path: "icon.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func cache() -> FaviconCache {
        FaviconCache(directory: library.folder.appending(path: "Favicons"))
    }

    @Test func `downloads an icon once and keeps it on disk`() async throws {
        let icon = try iconFile()

        let image = await cache().image(for: icon)
        try FileManager.default.removeItem(at: icon)
        let relaunched = await cache().image(for: icon)

        #expect(image != nil)
        #expect(relaunched != nil, "read from disk once the source is gone")
    }

    @Test func `keeps loaded icons in memory`() async throws {
        let icon = try iconFile()
        let cache = cache()
        #expect(cache.cachedImage(for: icon) == nil)

        _ = await cache.image(for: icon)

        #expect(cache.cachedImage(for: icon) != nil)
    }

    @Test func `gives nothing for an address that isn't an image`() async throws {
        let notImage = library.folder.appending(path: "page.html")
        try Data("<html></html>".utf8).write(to: notImage)

        #expect(await cache().image(for: notImage) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache().fileURL(for: notImage).path(percentEncoded: false)))
    }
}
