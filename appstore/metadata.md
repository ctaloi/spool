# App Store Connect — metadata cheat sheet

Paste these strings into the matching fields in App Store Connect. Each
field is sized to App Store's limits (noted in parens).

---

## App Name *(30 chars)*

```
Spool
```

## Subtitle *(30 chars)*

```
Hacker News, queued.
```

## Promotional Text *(170 chars — can be updated without re-review)*

```
On-device AI summaries you can edit. A hands-free audio queue that reads HN aloud. Zero tracking. The whole thing runs on your phone.
```

## Description *(4000 chars max — runs about 350 words below)*

```
Spool is a calm reader for Hacker News, built around three ideas: read it, hear it, all on your device.

READ IT
Every HN feed — Top, New, Best, Ask HN, Show HN, Jobs — with threaded comments, collapsible subtrees, and tap-to-collapse. Pull-to-refresh. Saved stories and read-tracking via SwiftData, indexed in Spotlight. Best-of windows for today, this week, this month, this year. A locally-computed Trending feed that watches score velocity between your visits — no background polling, no third-party telemetry.

HEAR IT
Add stories to your Spool. Tap Play All. Apple's on-device AI reads each one's article and discussion as conversational prose, in order. Sentence-by-sentence highlighting follows the spoken text. AirPods, CarPlay, and lock-screen controls all work. Pre-renders to your device so playback starts instantly. Skip, scrub, change voices.

ON-DEVICE AI
Tap Summarize on any thread. The on-device Foundation Models LLM produces a structured take on the article and a sentiment-aware digest of the discussion in seconds. No API keys, no cloud fallback, no data leaving your phone. Requires Apple Intelligence to be enabled.

EDITABLE PROMPTS
Spool ships with prompts tuned for HN, but every system prompt is editable in Settings. Don't like the framing? Rewrite it. Your edits stay on-device, versioned against the bundled defaults.

FOR HACKERS
Configurable home-screen widget pinned to any feed. Share extension. Siri shortcuts. iPad three-column with Liquid Glass. Editable AI prompts. Hide categories you don't read. Minimum-comments filter. Optional mention notifications. Open source under MIT.

SIGN IN (OPTIONAL)
Reading is anonymous. Signing in unlocks voting, posting, and replying. The login talks directly to news.ycombinator.com — cookies live in the system keychain, never on disk, never on any Spool server. There is no Spool server.

PRIVACY
No analytics. No crash reporters. No third-party SDKs. NSPrivacyTracking is set to false in the privacy manifest. The whole thing runs on your phone.

Requires iOS 26 and a device with Apple Intelligence for summary features.

Privacy policy: https://getspool.news/privacy/
Source code: https://github.com/ctaloi/spool

Not affiliated with Y Combinator. "Hacker News" is a trademark of Y Combinator.
```

## Keywords *(100 chars, comma-separated, no spaces around commas — Apple penalizes them)*

```
hn,reader,news,ai,summary,on-device,audio,podcast,liquid glass,swiftui,offline,privacy,foundation
```

## Support URL

```
https://github.com/ctaloi/spool/issues
```

## Marketing URL

```
https://getspool.news
```

## Privacy Policy URL

```
https://getspool.news/privacy/
```

---

## Category

- **Primary**: News
- **Secondary**: Productivity

## Age Rating

Run the questionnaire and answer:
- **Unrestricted Web Access** — Yes (article links open in Safari).
- **Frequent/Intense Mature/Suggestive Themes** — No.
- **Profanity or Crude Humor** — *Infrequent/Mild*. HN comments are mostly clean but the policy isn't.
- Everything else — No.

Expected rating: **17+**, primarily because of the Unrestricted Web Access answer.

## Pricing

**Free.** No IAPs. No tier selection.

## Availability

All countries (default), unless you have a reason to restrict.

## Export Compliance

In Build details when uploading:
- **Does your app use encryption?** Yes (HTTPS only, system frameworks).
- **Is it exempt under category 5 part 2?** Yes (uses only standard iOS HTTPS).
- Result: `ITSAppUsesNonExemptEncryption = false` — add this to `Info.plist` ahead of time so you never get the prompt:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

## App Privacy "Nutrition Label"

In App Store Connect → App Privacy → Get Started:

- **Does your app collect data from this app?** → **No**.

That's it. One radio button. The privacy manifest already declares no tracking, no API contacts that count as data collection, no third-party identifiers.

If a reviewer pushes back: HN's APIs are public and unauthenticated; the optional sign-in is direct to news.ycombinator.com without any intermediary Spool service. None of this counts as data collection per Apple's [definitions](https://developer.apple.com/app-store/app-privacy-details/).
