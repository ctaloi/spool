import Foundation
import os.log

private let prefetchGateLog = Logger(subsystem: "com.aloi.Spool", category: "PrefetchGate")

/// Coordinates between foreground user requests (manual Summarize
/// tap) and background prefetching (audio renders, summary
/// generation for queued items).
///
/// Apple's `LanguageModelSession` is effectively a single shared
/// resource — multiple inferences in flight queue up internally.
/// If a user taps Summarize while we're rendering the spool's
/// third audio item in the background, the foreground request
/// waits for that work to finish. That's the wrong tradeoff: the
/// user is actively asking for an answer right now.
///
/// `PrefetchGate.beginForeground()` cancels any in-flight
/// background tasks that registered themselves with the gate so
/// the LLM session (and CPU) frees up immediately. New background
/// tasks check `await waitForBackgroundSlot()` and block until
/// `endForeground()` releases.
///
/// One global instance. All actor operations are cheap — the gate
/// holds task handles, no heavy state.
actor PrefetchGate {
    static let shared = PrefetchGate()

    private var foregroundCount: Int = 0
    private var backgroundTasks: [Task<Void, Never>] = []
    private var backgroundWaiters: [CheckedContinuation<Void, Never>] = []

    /// Marks the start of a foreground (user-tap-driven) inference.
    /// Cancels any background tasks currently registered with the
    /// gate. Pair with `endForeground()` — typically via a `defer`.
    func beginForeground() {
        foregroundCount += 1
        if foregroundCount == 1 {
            let cancelled = backgroundTasks.count
            for task in backgroundTasks { task.cancel() }
            backgroundTasks.removeAll()
            if cancelled > 0 {
                prefetchGateLog.debug("Foreground active: cancelled \(cancelled, privacy: .public) background tasks")
            }
        }
    }

    /// Marks the end of a foreground inference. Resumes any
    /// background tasks waiting at `waitForBackgroundSlot()`.
    func endForeground() {
        guard foregroundCount > 0 else { return }
        foregroundCount -= 1
        if foregroundCount == 0 {
            let resumed = backgroundWaiters.count
            for cont in backgroundWaiters { cont.resume() }
            backgroundWaiters.removeAll()
            if resumed > 0 {
                prefetchGateLog.debug("Foreground idle: released \(resumed, privacy: .public) background waiters")
            }
        }
    }

    /// Whether a foreground request is currently active.
    var isForegroundActive: Bool { foregroundCount > 0 }

    /// Register a background `Task` with the gate so it can be
    /// cancelled when foreground takes over. Caller is responsible
    /// for calling `unregister` when the task completes naturally,
    /// otherwise the slot leaks until the next cancel sweep.
    func register(_ task: Task<Void, Never>) {
        backgroundTasks.append(task)
    }

    func unregister(_ task: Task<Void, Never>) {
        backgroundTasks.removeAll { $0 == task }
    }

    /// Block until foreground is idle. Use at the head of a
    /// background prefetch routine, and again at coarse-grained
    /// checkpoints between subtasks so a foreground tap doesn't
    /// have to wait for the next subtask to finish before getting
    /// CPU back.
    func waitForBackgroundSlot() async {
        guard foregroundCount > 0 else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            backgroundWaiters.append(cont)
        }
    }
}
