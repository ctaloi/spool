# SkimHN

A modern SwiftUI Hacker News reader with on-device AI summaries. iPhone +
iPad, iOS 26, Liquid Glass throughout. Reading is anonymous; signing in
unlocks voting, submitting, and replying.

## Highlights

- **Top / New / Best / Ask / Show / Jobs** feeds with infinite scroll.
- **Threaded comments** with collapsible subtrees, depth-indented color
  bars, and tap-to-collapse.
- **In-app Safari** for article URLs (`SFSafariViewController`).
- **On-device AI article summaries** — Apple Foundation Models
  (`LanguageModelSession`). No data leaves the device, no API keys.
- **On-device AI thread digest** — quick read-through of the discussion
  before you commit.
- **Saved Stories** + **read tracking** via SwiftData.
- **Search** via Algolia HN with Relevance / Newest sort scopes.
- **User profile view** — submissions, comments, karma, joined date.
- **Sign in to vote / submit / reply** — cookie auth scraped from the HN
  web flow; tokens live in `URLSession.shared.httpCookieStorage`, never
  on disk or in the codebase.
- **No telemetry, no tracking** — `NSPrivacyTracking: false`.

## Build

`SkimHN.xcodeproj` is generated, not checked in. Install
[XcodeGen](https://github.com/yonaskolb/XcodeGen) once, then regenerate
whenever files are added:

```sh
brew install xcodegen
cd ~/src/hacker-news
xcodegen generate
open SkimHN.xcodeproj
```

To build from the command line (force-point `xcode-select` at Xcode.app
if your system points at `CommandLineTools`):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SkimHN.xcodeproj -scheme SkimHN \
  -destination 'generic/platform=iOS Simulator' build
```

Deployment target is **iOS 26.0**. AI summaries require Apple
Intelligence to be enabled in Settings.

## Architecture

- **SwiftUI** for everything. `NavigationSplitView` is the root on both
  iPhone (compact) and iPad (regular). No tab bars; sidebar holds
  account, feeds, library, and post.
- **SwiftData** (`@Model`) for `SavedStory` and `ReadStory`.
- **Apple Foundation Models** for summaries. Errors are classified by
  `SummaryError.classify(_:)` into `.guardrail` / `.contextTooLong` /
  `.other` so the UI can show a useful fallback (Open Article button)
  when the on-device safety filter declines content.
- **Actor-wrapped networking** —
  `HNAPI` (Firebase API + `NSCache`), `HNSearchService` (Algolia),
  `HNUserService` (profile pages), `HNAuthService` (cookie auth +
  `fnid`/`hmac` scraping for vote/submit/reply), `ArticleFetcher`
  (HTML strip for the summarizer).
- **View models** are `@MainActor final class … ObservableObject`,
  owned via `@StateObject` and observed via `@ObservedObject`.

## Project layout

```
SkimHN/
  SkimHNApp.swift              @main; ModelContainer setup
  Theme.swift                  Color tokens + Typography
  Models/
    HNItem.swift               API item shape + HNStoryFeed
    HNUser.swift               profile shape
    Persistence.swift          @Model SavedStory / ReadStory
  Networking/
    HNAPI.swift                Firebase reader, cached
    HNSearchService.swift      Algolia search
    HNAuthService.swift        cookie auth, vote/submit/reply
    HNUserService.swift        user profile + activity
    ArticleFetcher.swift       HTML → plain text for summarizer
    SummaryService.swift       Foundation Models wrapper + error classifier
  ViewModels/
    StoryListViewModel.swift
    StoryDetailViewModel.swift
    SummaryViewModel.swift
    CommentsSummaryViewModel.swift
    SearchViewModel.swift
    AuthViewModel.swift
    UserProfileViewModel.swift
  Views/
    StoryListView.swift        Root: glass hero + inline search + list
    AppSidebar.swift           Account, feeds, saved, post, about
    StoryRowView.swift
    StoryDetailView.swift      Article + comments
    CommentView.swift          Depth-indented + collapse + reply
    CommentsSummaryCardView.swift
    SummaryCardView.swift
    HTMLText.swift             HN HTML → Markdown → AttributedString
    MarkdownText.swift         LLM markdown with section detection
    SavedStoriesView.swift
    UserProfileView.swift
    LoginView.swift / SubmitView.swift / ReplyView.swift
    VoteButton.swift
  AppIntents/
    SummarizeTopStoryIntent.swift   Siri shortcut
  Assets.xcassets              AccentColor (light/dark), AppIcon
  PrivacyInfo.xcprivacy
tools/
  make_icon.swift              Core Graphics AppIcon generator
```

## App Store positioning

- App display name (`CFBundleDisplayName`) is **"SkimHN"**. We avoid
  the full "Hacker News" string in any user-facing identifier to dodge
  trademark review.
- `PrivacyInfo.xcprivacy` declares
  `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) and
  `NSPrivacyTracking: false`.

## License

Personal project. Not yet open-sourced.
