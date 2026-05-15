import TipKit

/// First-launch teaching popovers that surface the app's less-obvious
/// features. Each tip is gated by a rule — typically "the user has
/// the relevant surface in front of them at least once" — and
/// auto-dismisses once the user actually performs the action.
///
/// Register via `Tips.configure(...)` in `SkimHNApp` so the engine
/// can persist seen state across launches.

/// Tap-the-pill discoverability for the Summarize button on a
/// loaded detail page. Fires once the user has opened a story (the
/// `detailViewed` event) but hasn't yet tapped Summarize.
struct SummarizeTip: Tip {
    static let detailViewed = Event(id: "skimhn.detail.viewed")
    static let summarizeTapped = Event(id: "skimhn.summarize.tapped")

    var title: Text {
        Text("On-device AI summary")
    }
    var message: Text? {
        Text("Tap Summarize for a fast take on the article and the discussion — generated on your device, never sent anywhere.")
    }
    var image: Image? {
        Image(systemName: "sparkles")
    }
    var rules: [Rule] {
        #Rule(Self.detailViewed) { $0.donations.count >= 1 }
        #Rule(Self.summarizeTapped) { $0.donations.count == 0 }
    }
}

/// Surface the swipe-right Save and Read Later actions. Fires after
/// the user has scrolled the list a few times but never used a swipe.
struct SwipeActionsTip: Tip {
    static let listScrolled = Event(id: "skimhn.list.scrolled")
    static let storySaved = Event(id: "skimhn.story.saved")

    var title: Text {
        Text("Swipe to save")
    }
    var message: Text? {
        Text("Swipe a row left for Save and Read Later. Right-edge gives you Share.")
    }
    var image: Image? {
        Image(systemName: "bookmark.fill")
    }
    var rules: [Rule] {
        #Rule(Self.listScrolled) { $0.donations.count >= 3 }
        #Rule(Self.storySaved) { $0.donations.count == 0 }
    }
}

/// Teaches the daily digest recall after the user has dismissed
/// one digest card. Without this hint the pill is easy to miss.
struct DigestRecallTip: Tip {
    static let digestDismissed = Event(id: "skimhn.digest.dismissed")
    static let digestRecalled = Event(id: "skimhn.digest.recalled")

    var title: Text {
        Text("Bring the digest back")
    }
    var message: Text? {
        Text("This pill regenerates today's digest any time. Tap to read what's on HN right now.")
    }
    var image: Image? {
        Image(systemName: "sparkles")
    }
    var rules: [Rule] {
        #Rule(Self.digestDismissed) { $0.donations.count >= 1 }
        #Rule(Self.digestRecalled) { $0.donations.count == 0 }
    }
}
