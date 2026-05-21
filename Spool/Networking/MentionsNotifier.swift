import Foundation
import UserNotifications
import BackgroundTasks

/// All the local-notification + background-refresh plumbing for the
/// Mentions feature lives here.
///
/// Two trackers are kept separate on purpose:
/// - `SeenMention` (SwiftData) — "the user opened this row in app";
///   clears the dot on the row.
/// - `NotifiedMentionStore` (UserDefaults) — "we already fired a
///   local notification for this reply"; prevents the BG handler
///   from double-notifying after the user has already seen the
///   reply in-app or after a previous BG run already alerted.
///
/// Intentionally `nonisolated` — the methods touch the network and
/// `UNUserNotificationCenter` only, never UI state. Forcing every
/// call to hop to the main actor would waste actor switches in the
/// hot BG path and could deadlock if main is busy.
enum MentionsNotifier {
    /// The single identifier registered in
    /// `BGTaskSchedulerPermittedIdentifiers`. Changing this requires
    /// a matching project.yml edit + reinstall.
    static let taskIdentifier = "news.getspool.app.refresh-mentions"

    /// Refresh cadence floor. iOS may run us later than this — never
    /// sooner. 30 minutes is the practical lower bound for
    /// BGAppRefreshTask without burning the system's runtime budget.
    static let refreshInterval: TimeInterval = 30 * 60

    // MARK: - Authorization

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        @unknown default:
            return false
        }
    }

    // MARK: - Test affordances

    /// Fires a representative notification 5 seconds out. The delay
    /// is deliberate — the user can lock the device or switch out of
    /// the app to see the notification land as it would in
    /// production. Throws a localized error if authorization is
    /// denied so the caller can surface it.
    static func sendTestNotification() async throws {
        guard await requestAuthorizationIfNeeded() else {
            throw NSError(
                domain: "MentionsNotifier",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Notifications are off. Enable them in iOS Settings → Spool to test."
                ]
            )
        }
        let content = UNMutableNotificationContent()
        content.title = "Test Mention"
        content.subtitle = "From a story you participated in"
        content.body = "tester replied: This is what a real reply notification will look like."
        content.sound = .default
        content.userInfo = ["feedSource": "mentions", "test": true]
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    /// Outcome of one check-and-notify pass. Lets the UI distinguish
    /// "no username" from "no new mentions" so the test button can
    /// say something meaningful in both cases.
    enum CheckOutcome {
        case noUsername
        case notificationsDenied
        case fired(count: Int)
        case skippedFirstRun(seeded: Int)
        case failed
    }

    /// Run the same pipeline the BG task runs — fetch fresh mentions
    /// for the signed-in user and post a notification for every
    /// reply we haven't notified about yet.
    ///
    /// Special case: the FIRST time this is ever called for a given
    /// install / user, we seed `NotifiedMentionStore` with every
    /// currently-visible reply ID instead of notifying. Without that
    /// pre-seed, every existing reply in the user's history would
    /// fire a notification on first run — a one-time flood of dozens
    /// to hundreds of notifications. We treat day-one as "we missed
    /// the live window for all of these, just remember them."
    @discardableResult
    static func runMentionsCheckAndNotify(username: String?) async -> CheckOutcome {
        guard let username, !username.isEmpty else { return .noUsername }
        guard await requestAuthorizationIfNeeded() else { return .notificationsDenied }
        guard let records = try? await HNMentionsService.shared.fetchMentions(for: username) else {
            return .failed
        }

        // First-run guard. Set the bookmark BEFORE seeding so a crash
        // mid-seed doesn't make us re-flood on the next try.
        if !NotifiedMentionStore.firstRunCompleted {
            NotifiedMentionStore.firstRunCompleted = true
            for record in records {
                NotifiedMentionStore.record(record.reply.id)
            }
            return .skippedFirstRun(seeded: records.count)
        }

        var fired = 0
        for record in records where !NotifiedMentionStore.contains(record.reply.id) {
            // iOS gives BG tasks ~30 seconds. If we're being killed
            // mid-loop, stop firing more notifications and let the
            // next run pick up where we left off.
            if Task.isCancelled { break }
            do {
                try await postMentionNotification(for: record)
                NotifiedMentionStore.record(record.reply.id)
                fired += 1
            } catch {
                // One failed post shouldn't tank the batch — keep going.
                continue
            }
        }
        return .fired(count: fired)
    }

    // MARK: - Background task scheduling

    /// Submit the next refresh request. Idempotent — submitting the
    /// same identifier replaces a pending request. Call on every
    /// app-background transition.
    ///
    /// Honors the user's `mentionNotificationsEnabled` toggle: if
    /// they've turned mentions off in Settings, we don't submit a
    /// request and any previously-scheduled one is cancelled.
    static func scheduleNextRefresh() {
        guard UserDefaults.standard.object(forKey: SettingsKeys.mentionNotificationsEnabled) == nil
                || UserDefaults.standard.bool(forKey: SettingsKeys.mentionNotificationsEnabled)
        else {
            cancelScheduledRefresh()
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Cancel any pending refresh request. Called when the user
    /// disables mention notifications in Settings.
    static func cancelScheduledRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - Notification body

    private static func postMentionNotification(for record: MentionRecord) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Reply from \(record.reply.by ?? "someone")"
        if let storyTitle = record.parentComment.storyTitle {
            content.subtitle = storyTitle
        }
        content.body = previewBody(from: record.reply.text)
        content.sound = .default
        content.userInfo = [
            "feedSource": "mentions",
            "replyID": record.reply.id,
            "storyID": record.parentComment.storyID,
        ]
        let request = UNNotificationRequest(
            identifier: "mention-\(record.reply.id)",
            content: content,
            // nil trigger fires immediately — the BG task already gives
            // us the right cadence; double-deferring would be noise.
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    /// Strip HTML and trim to a reasonable notification body length.
    /// HN comments are HTML-with-entity-escapes (`&quot;`, `&amp;`,
    /// `<p>`, `<i>`), which look broken when shown raw on the lock
    /// screen.
    private static func previewBody(from text: String?) -> String {
        guard let raw = text, !raw.isEmpty else { return "(no text)" }
        var stripped = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&#x27;", "'"),
            ("&nbsp;", " "),
        ]
        for (esc, char) in entities {
            stripped = stripped.replacingOccurrences(of: esc, with: char)
        }
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > 200 {
            return String(collapsed.prefix(200)) + "…"
        }
        return collapsed
    }
}

/// Set-membership store for "reply IDs we have already notified
/// about", backed by UserDefaults so it's reachable from the
/// background task without standing up a SwiftData container.
///
/// Caps to the most recent `capacity` IDs to prevent unbounded
/// growth — without the cap, a long-tenured user's store would
/// balloon over months. HN IDs are monotonically increasing, so
/// dropping the smallest IDs == dropping the oldest replies, which
/// are the least likely to receive new notification activity.
enum NotifiedMentionStore {
    private static let key = "mentions.notifiedReplyIDs"
    private static let firstRunKey = "mentions.firstRunCompleted"
    private static let capacity = 500

    static var all: Set<Int> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data)
        else { return [] }
        return decoded
    }

    static func contains(_ id: Int) -> Bool {
        all.contains(id)
    }

    static func record(_ id: Int) {
        var current = all
        current.insert(id)
        if current.count > capacity {
            // Drop the oldest (smallest) IDs in bulk. HN item IDs
            // are monotonic, so sort + suffix is the cheap path.
            let trimmed = Array(current).sorted().suffix(capacity)
            current = Set(trimmed)
        }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Whether we've ever run the check-and-notify pipeline before.
    /// Drives the first-run "seed, don't notify" path so the user
    /// isn't flooded by every existing reply on day one.
    static var firstRunCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: firstRunKey) }
        set { UserDefaults.standard.set(newValue, forKey: firstRunKey) }
    }
}
