import Foundation

enum MockData {
    static let collections: [BookmarkCollection] = [
        .init(id: "design", name: "Design"),
        .init(id: "engineering", name: "Engineering"),
        .init(id: "photography", name: "Photography"),
        .init(id: "reading", name: "Reading List"),
    ]

    private static func hoursAgo(_ hours: Double) -> Date {
        .now.addingTimeInterval(-hours * 3600)
    }

    // Mixed shapes so the gallery looks like a real feed: wide, tall, square.
    private static let mediaSizes: [(width: Int, height: Int)] = [
        (1200, 675), (1000, 1250), (1200, 900), (1080, 1080), (900, 1200),
    ]

    // Public 10-second test clips (1280x720). They have no poster images,
    // so the still is a placeholder photo.
    private static func sampleVideo(_ name: String) -> Bookmark.Media {
        .init(
            kind: .video,
            url: URL(string: "https://test-videos.co.uk/vids/\(name.lowercased().replacingOccurrences(of: "_", with: ""))/mp4/h264/720/\(name)_720_10s_1MB.mp4")!,
            posterURL: URL(string: "https://picsum.photos/seed/\(name)/1280/720")!,
            width: 1280,
            height: 720
        )
    }

    private static func post(
        _ id: String,
        name: String,
        handle: String,
        text: String,
        media: Int = 0,
        video: String? = nil,
        in collectionIDs: Set<String> = [],
        trashed: Bool = false,
        postedHoursAgo: Double,
        savedHoursAgo: Double
    ) -> Bookmark {
        Bookmark(
            id: id,
            url: URL(string: "https://x.com/\(handle)/status/\(id)")!,
            author: .init(name: name, handle: handle, avatarURL: nil),
            text: text,
            media: video.map { [sampleVideo($0)] } ?? (0..<media).map { index in
                let size = mediaSizes[(Int(id.suffix(2))! + index) % mediaSizes.count]
                return .init(
                    kind: .photo,
                    url: URL(string: "https://picsum.photos/seed/\(id)-\(index)/\(size.width)/\(size.height)")!,
                    width: Double(size.width),
                    height: Double(size.height)
                )
            },
            postedAt: hoursAgo(postedHoursAgo),
            savedAt: hoursAgo(savedHoursAgo),
            collectionIDs: collectionIDs,
            trashedAt: trashed ? hoursAgo(savedHoursAgo / 2) : nil
        )
    }

    static let bookmarks: [Bookmark] = [
        post("1843000000000000001", name: "Maya Chen", handle: "mayabuilds",
             text: "Shipped a SwiftUI app in a weekend. The trick was not fighting the defaults: NavigationSplitView, List, and .searchable get you 80% of a native Mac app for free.",
             media: 1, in: ["engineering"], postedHoursAgo: 30, savedHoursAgo: 2),
        post("1843000000000000002", name: "Devon Park", handle: "devonpark",
             text: "Hot take: most side projects die because the first version tries to sync. Build it local-first, add the server when you actually miss it.",
             in: ["engineering"], postedHoursAgo: 50, savedHoursAgo: 5),
        post("1843000000000000003", name: "Maya Chen", handle: "mayabuilds",
             text: "Thread on building Chrome extensions for X:\n\n1. Use a MutationObserver, the timeline is virtualized\n2. Parse at click time, not on render\n3. Never trust class names, use data-testid",
             in: ["engineering"], postedHoursAgo: 72, savedHoursAgo: 20),
        post("1843000000000000004", name: "Lena Ortiz", handle: "lenadraws",
             text: "New sketchbook pages. Trying gouache for the first time and it is humbling.",
             media: 3, in: ["design"], postedHoursAgo: 100, savedHoursAgo: 26),
        post("1843000000000000005", name: "Sam Rivera", handle: "samrivera",
             text: "Reading list for this week:\n- A Philosophy of Software Design\n- Designing Data-Intensive Applications (2nd ed)\n- The Mythical Man-Month, again",
             in: ["reading"], postedHoursAgo: 120, savedHoursAgo: 40),
        post("1843000000000000006", name: "Devon Park", handle: "devonpark",
             text: "SQLite is the right database for way more projects than people think. One file, zero ops, and it is fast.",
             in: ["engineering"], postedHoursAgo: 160, savedHoursAgo: 60),
        post("1843000000000000007", name: "Priya Nair", handle: "priyanair",
             text: "Sunrise from the ridge this morning. Worth the 4am alarm.",
             media: 1, in: ["photography"], postedHoursAgo: 200, savedHoursAgo: 90),
        post("1843000000000000008", name: "Sam Rivera", handle: "samrivera",
             text: "The best code review comment I ever got: \"What happens when this is empty?\" Ask it about every list, every string, every optional.",
             postedHoursAgo: 260, savedHoursAgo: 150),
        post("1843000000000000009", name: "Lena Ortiz", handle: "lenadraws",
             text: "Color palette I keep coming back to. Saving it here so I stop losing it.",
             media: 2, in: ["design"], postedHoursAgo: 400, savedHoursAgo: 220),
        post("1843000000000000010", name: "Priya Nair", handle: "priyanair",
             text: "If your app has a settings screen with more than 10 toggles, you have made decisions you should have made for the user.",
             in: ["design"], postedHoursAgo: 600, savedHoursAgo: 400),
        post("1843000000000000011", name: "Jordan Lee", handle: "jordanlee",
             text: "Keyboard shortcuts are a feature. Cmd+F, Cmd+R, Delete, Return to open. If a Mac app does not support them it does not feel like a Mac app.",
             trashed: true, postedHoursAgo: 800, savedHoursAgo: 700),
        post("1843000000000000012", name: "Maya Chen", handle: "mayabuilds",
             text: "Demo day slides are up. Thanks everyone who came by!",
             media: 4, trashed: true, postedHoursAgo: 1000, savedHoursAgo: 900),
        post("1843000000000000013", name: "Lena Ortiz", handle: "lenadraws",
             text: "Studio corner, finally organized.",
             media: 1, in: ["photography"], postedHoursAgo: 8, savedHoursAgo: 1),
        post("1843000000000000014", name: "Priya Nair", handle: "priyanair",
             text: "Fog rolling over the bay. No filter.",
             media: 1, in: ["photography"], postedHoursAgo: 14, savedHoursAgo: 3),
        post("1843000000000000015", name: "Jordan Lee", handle: "jordanlee",
             text: "Moodboard for the new landing page. Warm neutrals, lots of whitespace, one loud accent.",
             media: 2, in: ["design"], postedHoursAgo: 40, savedHoursAgo: 12),
        post("1843000000000000016", name: "Devon Park", handle: "devonpark",
             text: "A good empty state tells you what goes here and how to put something there. That's it. Two sentences.",
             in: ["design"], postedHoursAgo: 90, savedHoursAgo: 30),
        post("1843000000000000017", name: "Maya Chen", handle: "mayabuilds",
             text: "Weekend hike, phone stayed in the bag for most of it.",
             media: 1, in: ["photography"], postedHoursAgo: 130, savedHoursAgo: 70),
        post("1843000000000000018", name: "Sam Rivera", handle: "samrivera",
             text: "Desk setup v4. Smaller monitor, bigger plant.",
             media: 1, postedHoursAgo: 300, savedHoursAgo: 180),
        post("1843000000000000019", name: "Lena Ortiz", handle: "lenadraws",
             text: "Packaging study for a friend's ceramics shop.",
             media: 1, postedHoursAgo: 20, savedHoursAgo: 4),
        post("1843000000000000020", name: "Priya Nair", handle: "priyanair",
             text: "Light through the studio window at 5pm.",
             media: 1, postedHoursAgo: 60, savedHoursAgo: 15),
        post("1843000000000000021", name: "Jordan Lee", handle: "jordanlee",
             text: "Product shots for the launch. Shot on a white sweep with one softbox.",
             media: 2, in: ["design"], postedHoursAgo: 110, savedHoursAgo: 45),
        post("1843000000000000022", name: "Maya Chen", handle: "mayabuilds",
             text: "Found an old notebook from 2019 with the first sketch of this app.",
             media: 1, postedHoursAgo: 180, savedHoursAgo: 80),
        post("1843000000000000023", name: "Jordan Lee", handle: "jordanlee",
             text: "Motion study for the onboarding screens. Loop it a few times.",
             video: "Jellyfish", in: ["design"], postedHoursAgo: 6, savedHoursAgo: 2),
        post("1843000000000000024", name: "Priya Nair", handle: "priyanair",
             text: "Drone footage from the coast last weekend.",
             video: "Sintel", in: ["photography"], postedHoursAgo: 26, savedHoursAgo: 9),
        post("1843000000000000025", name: "Devon Park", handle: "devonpark",
             text: "30 second demo of the new sync engine.",
             video: "Big_Buck_Bunny", in: ["engineering"], postedHoursAgo: 70, savedHoursAgo: 25),
    ]
}
