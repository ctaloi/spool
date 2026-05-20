import Foundation

extension HNItem {
    /// Fake stories used to render the widget's placeholder /
    /// preview state when the timeline hasn't been populated yet
    /// (first install, gallery preview, no network on first launch).
    static let widgetPlaceholders: [HNItem] = [
        HNItem(
            id: 1, type: "story", by: "pg", time: nil, text: nil,
            url: "https://example.com", title: "Why Hacker News matters",
            score: 1234, descendants: 200,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
        HNItem(
            id: 2, type: "story", by: "patio11", time: nil, text: nil,
            url: "https://example.com", title: "A field guide to writing useful software",
            score: 800, descendants: 120,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
        HNItem(
            id: 3, type: "story", by: "tptacek", time: nil, text: nil,
            url: "https://example.com", title: "On reading the source code",
            score: 540, descendants: 75,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
        HNItem(
            id: 4, type: "story", by: "danluu", time: nil, text: nil,
            url: "https://example.com", title: "Latency numbers every programmer should know",
            score: 410, descendants: 55,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
        HNItem(
            id: 5, type: "story", by: "antirez", time: nil, text: nil,
            url: "https://example.com", title: "Thoughts on distributed systems",
            score: 300, descendants: 45,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
        HNItem(
            id: 6, type: "story", by: "jvns", time: nil, text: nil,
            url: "https://example.com", title: "Practical advice for debugging",
            score: 220, descendants: 30,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        ),
    ]
}
