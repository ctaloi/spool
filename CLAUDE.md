# SkimHN — project guide for AI assistants

A SwiftUI Hacker News reader for iPhone + iPad with on-device AI summaries.
This document orients you to the codebase fast — read it before doing any
substantive work.

## Product principles (do not violate)

1. **Simplicity over features.** Every screen should pass the "calm test" —
   one clear primary action, quiet meta information.
2. **Readability first.** Body text uses iOS text styles so it scales with
   Dynamic Type. Don't hard-code font sizes for body content.
3. **iOS-native patterns.** Prefer Apple's controls (`NavigationSplitView`,
   `Form`, `ContentUnavailableView`, sheets) over custom chrome.
4. **No telemetry, no tracking.** `NSPrivacyTracking: false` in
   `PrivacyInfo.xcprivacy`. Don't add analytics SDKs.

## Tech stack

- SwiftUI, deployment target **iOS 26.0**. The app is iOS 26-only — use
  Liquid Glass APIs (`.buttonStyle(.glass)`, `.glassEffect(_:in:)`,
  `ToolbarSpacer`, `onScrollGeometryChange`) directly. Do **not** add
  `@available(iOS 26.0, *)` checks or fallbacks for older OSes.
- SwiftData (`@Model`) for local persistence — `SavedStory`, `ReadStory`.
- Apple Foundation Models for AI summaries via `LanguageModelSession`.
  Import `FoundationModels` directly — no `canImport` guards needed.
  Wrap errors through `SummaryError.classify(_:)` so guardrail / context
  overflow are surfaced with kind-specific UI in the summary cards.
- Project is generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  After adding files run `xcodegen generate`; never hand-edit
  `SkimHN.xcodeproj`.

## Build

```sh
brew install xcodegen          # one time
cd ~/src/hacker-news
xcodegen generate
open SkimHN.xcodeproj
```

### Code signing

`DEVELOPMENT_TEAM` lives in `Configs/Signing.xcconfig`, not in
`project.yml`. xcodegen reads the xcconfig but never writes to it,
so your team ID survives every `xcodegen generate`.

One-time setup per clone:

```sh
# Edit Configs/Signing.xcconfig and set DEVELOPMENT_TEAM = your-team-id.
# Then tell git to ignore your local edits:
git update-index --skip-worktree Configs/Signing.xcconfig
```

To unstash and pull schema changes from main, reverse it with
`git update-index --no-skip-worktree Configs/Signing.xcconfig`.

Never set `DEVELOPMENT_TEAM` in `project.yml` — that file regenerates
the `.pbxproj`, which overwrites the signing block on every run and
resets the team to None.

To build from the command line (this machine's `xcode-select` points at
`CommandLineTools`, which lacks `xcodebuild`; force-point at Xcode.app):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SkimHN.xcodeproj -scheme SkimHN \
  -destination 'generic/platform=iOS Simulator' build
```

`swiftc -parse <file>` is a cheap syntax-only sanity check, but it can't
resolve cross-file types; for real verification use the `xcodebuild`
command above.

## File layout

```
SkimHN/
  SkimHNApp.swift            @main; ModelContainer setup
  Theme.swift                Colors + Theme.Typography tokens
  Models/
    HNItem.swift             API item shape + HNStoryFeed enum
    Persistence.swift        @Model SavedStory / ReadStory
  Networking/                actors wrapping HN/Algolia/Apple APIs
    HNAPI.swift              Firebase reader (NSCache-backed)
    HNSearchService.swift    Algolia search
    HNAuthService.swift      Cookie auth + vote / submit / reply
    ArticleFetcher.swift     Strip HTML for the summarizer
    SummaryService.swift     Apple Foundation Models wrapper
  ViewModels/                @MainActor ObservableObjects
    StoryListViewModel.swift
    StoryDetailViewModel.swift
    SummaryViewModel.swift
    CommentsSummaryViewModel.swift
    SearchViewModel.swift
    AuthViewModel.swift
  Views/
    StoryListView.swift      Root: NavigationSplitView (sidebar/content/detail)
    AppSidebar.swift         Sidebar: Account / Categories / Reading List / Post / About
    StoryRowView.swift       Single feed/search row
    StoryDetailView.swift    Article view with comments
    CommentView.swift        Single comment + collapse + reply
    CommentsSummaryCardView.swift
    SummaryCardView.swift
    HTMLText.swift           HN HTML → Markdown → AttributedString
    MarkdownText.swift       LLM markdown rendering with section detection
    SavedStoriesView.swift
    LoginView.swift / SubmitView.swift / ReplyView.swift
    VoteButton.swift
  AppIntents/
    SummarizeTopStoryIntent.swift   Siri shortcut
  Assets.xcassets            AccentColor (light/dark), AppIcon
  PrivacyInfo.xcprivacy
tools/
  make_icon.swift            Core Graphics script for AppIcon
```

## Architecture patterns to follow

### NavigationSplitView is the root

Both iPhone (compact) and iPad (regular) use one `NavigationSplitView` in
`StoryListView`. Sidebar = `AppSidebar`. Content = `listContent` (the feed
/ search list). Detail = `StoryDetailView`. Story selection is driven by
`@State selectedStory: HNItem?` plus `.tag(story)` on rows in a
`List(selection:)`. Edge-swipe is handled by `NavigationSplitView` — do
not build custom drawer overlays.

### View-model lifecycle

- View models are `@MainActor final class … ObservableObject`. Owned via
  `@StateObject` in the view that creates them, observed via
  `@ObservedObject` when injected.
- All side-effect-y methods are `async` so views drive them via
  `.task { … }` or `Task { … }`. If a `.task` is being cancelled by a
  navigation transition you can swap to `.onAppear { Task { … } }` to
  detach (see `StoryDetailView`).

### Loading errors

If `CancellationError` / `URLError.cancelled` would otherwise surface as
"the operation couldn't be completed" in the UI, swallow it explicitly
(`isCancellation(_:)` helper in `StoryDetailViewModel`). Real errors go
into an `@Published errorMessage` and render via `ContentUnavailableView`
with a Retry button.

### Comment tree loading

Two-phase progressive load in `StoryDetailViewModel.loadComments`:
1. Fetch parent item and the top-level comments — display immediately.
2. Fetch each subtree in parallel via `withTaskGroup`, splice in via
   `insertSubtree(_:after:)`.

### AI summaries

`SummaryViewModel` shrinks the article on context-window overflow
(starts 6 000 chars, halves to a 1 500 floor). `MarkdownText` softens
SwiftUI's default `.bold` to `.semibold` (less shouty) and promotes
`**Label** — body` paragraphs / bullets into real section headings with
extra spacing. Section labels render as small uppercase eyebrow.

### Auth scraping

`HNAuthService` POSTs to `news.ycombinator.com` directly because there's
no official API. It scrapes `auth` tokens from item pages and `hmac`
from `/submit` and `/reply`. Always normalize `&amp;` → `&` before regex
matching (HN HTML-entity-escapes ampersands in links).

## App Store readiness

- `PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults`
  with reason `CA92.1` and `NSPrivacyTracking: false`.
- `AccentColor` is a color set with light + dark variants — use
  `Color("AccentColor")` (wrapped in `Theme.accent`).
- App display name (`CFBundleDisplayName`) is **"SkimHN"**. The full
  "Hacker News" string is avoided in any user-facing identifier to dodge
  trademark review.
- Launch screen uses `INFOPLIST_KEY_UILaunchScreen_BackgroundColor:
  systemBackground`.

## Conventions

- No emojis in code or comments unless requested.
- Comments explain *why*, not *what*. Skip them entirely if the
  identifiers already say it.
- For UI work, parse-check with `swiftc -parse` after each meaningful
  edit. If full Xcode is available, `xcodebuild -project SkimHN.xcodeproj
  -scheme SkimHN build` is the truth.
- Don't surface AI summaries automatically — they fire when the user
  taps Summarize. The brand promise is "Skim", not "auto-skim".

## Out-of-scope (don't add without asking)

- Tab bars. Settings + categories + library all live in the sidebar.
- Custom drawer overlays. Use `NavigationSplitView`.
- Account-required gates beyond what HN itself enforces (vote / submit /
  reply). Reading is always available.
- Third-party dependencies. The app is pure SwiftUI + Foundation.
