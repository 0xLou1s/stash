import Foundation

/// What a saved link shows: the page's title and favicon.
struct LinkMetadata: Equatable, Sendable {
    var title: String?
    var iconURL: URL?
}

/// Reads a page's `<head>` for its title and favicon. Plain HTML only; a page
/// that builds its title with JavaScript keeps the name it was saved with.
nonisolated enum LinkMetadataFetcher {
    @concurrent
    static func fetch(_ url: URL) async -> LinkMetadata? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }

        // Redirects change the base relative icon paths resolve against.
        let pageURL = response.url ?? url
        guard response.mimeType?.contains("html") ?? true else {
            return LinkMetadata(title: nil, iconURL: defaultIconURL(for: pageURL))
        }
        // Everything needed is in the head, which comes first.
        let html = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
        return parse(html: html, pageURL: pageURL)
    }

    static func parse(html: String, pageURL: URL) -> LinkMetadata {
        let head = html.firstRange(of: "</head>").map { String(html[..<$0.lowerBound]) } ?? html
        return LinkMetadata(title: title(in: head), iconURL: iconURL(in: head, pageURL: pageURL))
    }

    // MARK: - Title

    private static func title(in head: String) -> String? {
        let titleTag = #/<title[^>]*>(.*?)</title>/#.ignoresCase().dotMatchesNewlines()
        if let match = head.firstMatch(of: titleTag), let title = cleaned(match.1) {
            return title
        }
        // Some single-page apps leave <title> empty and only fill in Open Graph.
        let ogTitle = tags(matching: #/<meta\b[^>]*>/#.ignoresCase(), in: head).first { $0["property"] == "og:title" }?["content"]
        return ogTitle.flatMap { cleaned($0[...]) }
    }

    private static func cleaned(_ text: Substring) -> String? {
        let decoded = decodingEntities(String(text))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return decoded.isEmpty ? nil : decoded
    }

    private static let namedEntities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    /// The few entities that show up in titles: named basics and numeric ones.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(#/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);/#) { match in
            let name = match.1
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init) ?? String(match.0)
            }
            if name.hasPrefix("#") {
                return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init) ?? String(match.0)
            }
            return namedEntities[name.lowercased()] ?? String(match.0)
        }
    }

    // MARK: - Icon

    private static func iconURL(in head: String, pageURL: URL) -> URL? {
        struct Candidate {
            let url: URL
            let isTouchIcon: Bool
            /// The largest declared side, or 0 when `sizes` is missing.
            let size: Int
        }

        let candidates: [Candidate] = tags(matching: #/<link\b[^>]*>/#.ignoresCase(), in: head).compactMap { attributes in
            let rel = Set((attributes["rel"] ?? "").lowercased().split(separator: " "))
            guard rel.contains("icon") || rel.contains("apple-touch-icon"),
                  let href = attributes["href"],
                  let url = URL(string: decodingEntities(href), relativeTo: pageURL)?.absoluteURL,
                  ["http", "https"].contains(url.scheme)
            else { return nil }
            // Image views can't draw SVG.
            if attributes["type"] == "image/svg+xml" || url.pathExtension.lowercased() == "svg" { return nil }

            let size = (attributes["sizes"] ?? "")
                .split(separator: " ")
                .compactMap { Int($0.lowercased().split(separator: "x").first ?? "") }
                .max() ?? 0
            return Candidate(url: url, isTouchIcon: !rel.contains("icon"), size: size)
        }

        // A plain icon near 32–64 px looks best at row size; touch icons are a
        // fallback, since they're often a tile with a background.
        let best = candidates.min { lhs, rhs in
            func score(_ candidate: Candidate) -> (Int, Int) {
                let fit = candidate.size == 0 ? 1 : (candidate.size >= 32 ? 0 : 2)
                return (candidate.isTouchIcon ? 1 : 0, fit * 10_000 + abs(candidate.size - 64))
            }
            return score(lhs) < score(rhs)
        }
        return best?.url ?? defaultIconURL(for: pageURL)
    }

    /// Where browsers look when a page names no icon.
    private static func defaultIconURL(for pageURL: URL) -> URL? {
        URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
    }

    // MARK: - Tags

    /// The attributes of every tag `tag` matches, with lowercased attribute names.
    private static func tags(matching tag: Regex<Substring>, in html: String) -> [[String: String]] {
        let attribute = #/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/#
        return html.matches(of: tag).map { match in
            var attributes: [String: String] = [:]
            for pair in html[match.range].matches(of: attribute) {
                let value = pair.2 ?? pair.3 ?? pair.4 ?? ""
                attributes[pair.1.lowercased()] = value.trimmingCharacters(in: .whitespaces)
            }
            return attributes
        }
    }
}
