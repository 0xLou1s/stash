import AppKit
import CryptoKit

/// Site icons, downloaded once and kept on disk and in memory, so bookmarks
/// show their icons straight away instead of fetching them on every launch.
///
/// Files live in Caches: the system may clear them, and they're fetched again.
final class FaviconCache {
    static let shared = FaviconCache()

    private let directory: URL
    private let session: URLSession
    private let memory = NSCache<NSURL, NSImage>()
    /// One download per icon, however many rows ask for it at once.
    private var loading: [URL: Task<NSImage?, Never>] = [:]
    /// Icons that couldn't be loaded this session; not retried until relaunch.
    private var failed: Set<URL> = []

    init(
        directory: URL = URL.cachesDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Stash", directoryHint: .isDirectory)
            .appending(path: "Favicons", directoryHint: .isDirectory),
        session: URLSession = .shared
    ) {
        self.directory = directory
        self.session = session
    }

    /// The icon if it's already in memory, for drawing without a placeholder flash.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    /// The icon from memory, disk, or the web, in that order. Nil if it can't be loaded.
    func image(for url: URL) async -> NSImage? {
        if let image = cachedImage(for: url) { return image }
        guard !failed.contains(url) else { return nil }
        if let task = loading[url] { return await task.value }

        let task = Task { await load(url) }
        loading[url] = task
        let image = await task.value
        loading[url] = nil

        if let image {
            memory.setObject(image, forKey: url as NSURL)
        } else {
            failed.insert(url)
        }
        return image
    }

    private func load(_ url: URL) async -> NSImage? {
        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            return image
        }

        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let image = NSImage(data: data)
        else { return nil }

        // Not worth an error: without the file, the icon is fetched again next launch.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return image
    }

    /// Named by a hash of the address, which may be long or contain any character.
    func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: hash)
    }
}
