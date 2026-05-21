# App Review Notes

Paste into App Store Connect → App Review Information → Notes.

---

```
Spool is a Hacker News reader for iOS 26. Three notes for review:

1. SIGN-IN IS OPTIONAL. Reading and AI summaries work without an account. Tapping Sign In posts the user's credentials directly to https://news.ycombinator.com/login — the standard HN web login. The session cookie HN returns is stored in URLSession.shared.httpCookieStorage (system keychain). The app does not proxy this traffic, does not transmit credentials to any other server, and has no Spool backend. Sign-in unlocks voting/posting/replying via the same cookie-authenticated endpoints HN's own website uses.

2. AI SUMMARY FEATURES RUN ON-DEVICE via Apple Foundation Models (LanguageModelSession). They are gated on Apple Intelligence being enabled in iOS Settings. To test summary features on the review device, please:
   - Open Settings → Apple Intelligence & Siri → enable Apple Intelligence.
   - Open any story in Spool → tap Summarize at the top of the article.
   - Or queue 1-2 stories to the Spool (headphones icon) → tap Play All to hear the audio queue.

3. HACKER NEWS TRADEMARK. The app's display name is "Spool" — chosen specifically to avoid claiming "Hacker News" as our own. Descriptive use ("a reader for Hacker News") is the only place the phrase appears in marketing copy, consistent with nominative fair use. There is no Y Combinator affiliation claim.

A test account isn't needed to review the app — every feature except voting/posting/replying works without one. If you want to verify the sign-in flow without your own HN account, please contact support and we can provide a test account.

Repository: https://github.com/ctaloi/spool (MIT)
Privacy policy: https://getspool.news/privacy/
```

---

## If asked: contact info

- Support email: whatever email the developer profile uses (App Store Connect picks it up automatically).
- If reviewer pings for a test HN account: create a throwaway at news.ycombinator.com/login, provide it via the App Review notes field.

## Common review pushbacks + responses

**"This app appears to scrape Hacker News rather than use an official API."**
> The Firebase Realtime DB endpoint at hacker-news.firebaseio.com is HN's official public API ([docs](https://github.com/HackerNews/API)). All read traffic uses it. The sign-in flow uses HN's standard web login because HN does not offer a write API — this is the same auth path the HN website itself uses.

**"Your app duplicates a website without adding value."**
> Spool adds on-device AI summaries (Apple Foundation Models), an audio queue (AVSpeechSynthesizer + cached AVAudioPlayer rendering), threaded-comment Q&A, Spotlight integration, Siri shortcuts, configurable widgets, and a Liquid Glass three-column iPad layout. None of these exist on news.ycombinator.com.

**"Apple Intelligence is a system feature."**
> Acknowledged. Summary features show a clear "Enable Apple Intelligence" prompt when the system feature is disabled; reading and audio playback (which uses AVSpeechSynthesizer, not Apple Intelligence) work without it.
