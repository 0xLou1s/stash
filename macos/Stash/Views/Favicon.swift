import SwiftUI

/// A site's icon at row size, or a globe until (or unless) it loads.
struct Favicon: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            // Memory first, so a row scrolled back into view doesn't flash the globe.
            if let image = image ?? url.flatMap(FaviconCache.shared.cachedImage(for:)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await FaviconCache.shared.image(for: url)
        }
    }
}
