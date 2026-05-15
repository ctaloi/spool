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
@MainActor
enum MentionsNotifier {
    /// The single identifier registered in
    /// `BGTaskSchedulerPermittedIdentifiers`. Changing this requires
    /// a matching project.yml edit + reinstall.
    static let taskIdentifier = "com.aloi.SkimHN.refresh-mentions"

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
                        "Notifications are off. Enable them in iOS Settings → SkimHN to test."
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

    /// Run the same pipeline the BG task runs — fetch fresh mentions
    /// for the signed-in user and post a notification for every
    /// reply we haven't notified about yet. Returns the count of new
    /// notifications fired so the caller can show a confirmation.
    @discardableResult
    static func runMentionsCheckAndNotify(username: String?) async -> Int {
        guard let username, !username.isEmpty else { return 0 }
        guard await requestAuthorizationIfNeeded() else { return 0 }
        guard let records = try? await HNMentionsService.shared.fetchMentions(for: username) else {
            return 0
        }
        var fired = 0
        for record in records where !NotifiedMentionStore.contains(record.reply.id) {
            do {
                try await postMentionNotification(for: record)
                NotifiedMentionStore.record(record.reply.id)
                fired += 1
            } catch {
                // Skip but keep trying the rest — one failed post
                // shouldn't tank the batch.
                continue
            }
        }
        return fired
    }

    // MARK: - Background task scheduling

    /// Submit the next refresh request. Idempotent — submitting the
    /// same identifier replaces a pending request. Call on every
    /// app-background transition.
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
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
        // Cheap HTML strip — drops tags + decodes the most common
        // entities. Good enough for a notification preview.
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
enum NotifiedMentionStore {
    private static let key = "mentions.notifiedReplyIDs"

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
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
