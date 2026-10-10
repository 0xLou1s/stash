import Foundation
import Testing
@testable import Stash

@Suite("Reading a page's title and icon")
struct LinkMetadataTests {
    let page = URL(string: "https://example.com/docs/page")!

    private func parse(_ head: String) -> LinkMetadata {
        LinkMetadataFetcher.parse(html: "<html><head>\(head)</head><body><title>Not this</title></body></html>", pageURL: page)
    }

    @Test func `reads the title, decoding entities and tidying whitespace`() {
        let metadata = parse("<TITLE lang=en>\n  Avatar Circles &amp; More &#8212; Magic&nbsp;UI &#x2728;\n</TITLE>")
        #expect(metadata.title == "Avatar Circles & More — Magic UI ✨")
    }

    @Test func `falls back to Open Graph when the title is empty`() {
        let metadata = parse(#"<title> </title><meta property="og:title" content="React Bits">"#)
        #expect(metadata.title == "React Bits")
    }

    @Test func `resolves a relative icon against the page`() {
        let metadata = parse(#"<link rel="icon" href="/static/favicon.png">"#)
        #expect(metadata.iconURL?.absoluteString == "https://example.com/static/favicon.png")
    }

    @Test func `prefers a plain icon near row size over a touch icon or SVG`() {
        let metadata = parse("""
        <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
        <link rel='icon' type='image/svg+xml' href='/icon.svg'>
        <link rel="icon" href="/16.png" sizes="16x16">
        <link rel="shortcut icon" href="/64.png" sizes="64x64">
        """)
        #expect(metadata.iconURL?.lastPathComponent == "64.png")
    }

    @Test func `uses favicon.ico when the page names no icon`() {
        let metadata = parse("<title>Plain</title>")
        #expect(metadata.iconURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test(arguments: [
        ("ui.aceternity.com", "https://ui.aceternity.com"),
        ("  https://magicui.design/docs  ", "https://magicui.design/docs"),
        ("http://localhost:3000", "http://localhost:3000"),
    ])
    func `reads typed and pasted addresses`(text: String, expected: String) {
        #expect(URL(webAddress: text)?.absoluteString == expected)
    }

    @Test(arguments: ["", "not a url", "file:///etc/hosts", "javascript:alert(1)", "notahost"])
    func `rejects what isn't a web page`(text: String) {
        #expect(URL(webAddress: text) == nil)
    }
}
