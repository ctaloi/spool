import CryptoKit
import Foundation
import AVFoundation
import os.log

private let audioCacheLog = Logger(subsystem: "news.getspool.app", category: "AudioCache")

/// Identifies a single rendered TTS take. Includes everything that can
/// change the audible output so a content change, a voice swap, or a
/// playback-rate tweak each produces a distinct cache entry.
struct AudioCacheKey: Hashable, CustomStringConvertible {
    let storyID: Int
    /// SHA256 of the cleaned script text. Story ID alone isn't enough
    /// because the script changes when summaries get re-prefetched or
    /// the user edits the system prompt.
    let scriptHash: String
    /// Stable voice identifier (`AVSpeechSynthesisVoice.identifier`).
    /// Empty string is used when no voice was selected, so we don't
    /// reuse the same key for a voiceless render.
    let voiceID: String
    /// Quantized playback rate. We round to 0.05 to avoid spawning a
    /// new cache entry every time the slider nudges by a hair.
    let rateQuantum: Int

    init(storyID: Int, script: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        self.storyID = storyID
        self.scriptHash = Self.hash(of: script)
        self.voiceID = voice?.identifier ?? ""
        // 0.05 quantum on a 0...1 input → 20 distinct buckets. Plenty
        // of fidelity for the player's rate slider.
        self.rateQuantum = Int((rate * 20).rounded())
    }

    /// Filename-safe identifier used for the cached files.
    var filename: String {
        let voice = voiceID.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "s\(storyID)_\(scriptHash.prefix(12))_\(voice)_r\(rateQuantum)"
    }

    var description: String { filename }

    private static func hash(of text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// A cached audio render — both the audio file and the timestamp
/// metadata read back from disk. Returned by `AudioCache.lookup` so
/// callers don't have to recompute paths.
struct CachedAudio {
    let key: AudioCacheKey
    let audioURL: URL
    let duration: TimeInterval
    let timestamps: [AudioTimestamp]
}

/// On-disk store for pre-rendered TTS audio. Lives in the app's
/// caches directory, so iOS can evict it under storage pressure
/// without losing any user data. Keyed by `AudioCacheKey` so
/// re-rendering only happens when something audible changed.
///
/// The store is intentionally simple: one `.caf` per render plus a
/// sibling `.json` for the timestamps. We don't keep an in-memory
/// index — every lookup does a small file-attribute read, which is
/// cheap on iOS's local filesystem and lets the cache survive app
/// restarts without rehydration.
actor AudioCache {
    static let shared = AudioCache()

    private let fileManager = FileManager.default
    /// Directory where renders live. Lazily created on first use.
    let rootURL: URL

    /// Soft cap on total bytes stored. `enforceQuota` evicts oldest
    /// renders past this. iOS may also evict the whole directory
    /// without telling us — callers must treat lookup as a miss
    /// even after store.
    private let maxBytes: Int64

    /// Per-key serialization for active renders. Without this, two
    /// concurrent prefetches for the same story can both pass the
    /// lookup short-circuit, both call `reserveOutputURL` (which
    /// removes any existing file), and stomp each other mid-write —
    /// producing a corrupted .caf. `claimRender` returns false when
    /// another render for the same key is in flight; the caller
    /// should skip and let the leader populate the cache.
    private var inFlightRenders: Set<AudioCacheKey> = []

    /// Continuation queue for the global "one render at a time" gate.
    /// AVSpeechSynthesizer.write isn't dramatically faster than
    /// real-time playback for higher-quality voices, and running
    /// multiple renders concurrently produces more contention than
    /// throughput. Each prefetch await's `waitForRenderSlot()`
    /// before starting; the slot is released via `releaseRenderSlot()`
    /// (paired in a defer at the call site).
    private var renderSlotBusy: Bool = false
    private var renderSlotWaiters: [CheckedContinuation<Void, Never>] = []

    init(maxBytes: Int64 = 200 * 1024 * 1024) {
        // 200 MB cap by default. A 5-minute summary renders to ~3 MB
        // of mono 22 kHz CAF — that's room for ~60 prefetched items.
        self.maxBytes = maxBytes
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.rootURL = caches.appendingPathComponent("SpoolAudio", isDirectory: true)
    }

    // MARK: - Layout

    private func audioURL(for key: AudioCacheKey) -> URL {
        rootURL.appendingPathComponent("\(key.filename).caf")
    }

    private func metaURL(for key: AudioCacheKey) -> URL {
        rootURL.appendingPathComponent("\(key.filename).json")
    }

    private func ensureRootExists() throws {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Lookup / store

    /// Returns the cached render if both the audio and metadata files
    /// exist on disk. Refreshes the audio file's modification date so
    /// LRU eviction keeps recently-used items.
    func lookup(_ key: AudioCacheKey) -> CachedAudio? {
        let audio = audioURL(for: key)
        let meta = metaURL(for: key)
        guard fileManager.fileExists(atPath: audio.path),
              fileManager.fileExists(atPath: meta.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: meta)
            let stored = try JSONDecoder().decode(StoredMetadata.self, from: data)
            // Touch the audio file's mtime so LRU keeps it.
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: audio.path
            )
            return CachedAudio(
                key: key,
                audioURL: audio,
                duration: stored.duration,
                timestamps: stored.timestamps
            )
        } catch {
            audioCacheLog.error("Failed to read cache metadata for \(key.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Treat a corrupt metadata file as a miss and clean up so
            // the next render can replace both halves.
            try? fileManager.removeItem(at: audio)
            try? fileManager.removeItem(at: meta)
            return nil
        }
    }

    /// Returns the audio output URL that a renderer should write to
    /// for this key. Creates the cache directory on demand. The
    /// caller is expected to invoke `finalize(_:)` after the render
    /// succeeds so the timestamp metadata is persisted alongside.
    func reserveOutputURL(for key: AudioCacheKey) throws -> URL {
        try ensureRootExists()
        let url = audioURL(for: key)
        // Clear any stale file so AVAudioFile starts clean. iOS does
        // not overwrite-by-default when given an existing path.
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        return url
    }

    /// Writes the timestamp metadata next to the audio file produced
    /// by a render. Returns the `CachedAudio` ready to hand to the
    /// player. Throws if the audio file is missing — guarding
    /// against orphaned metadata.
    func finalize(_ result: AudioRenderResult, key: AudioCacheKey) throws -> CachedAudio {
        let audio = audioURL(for: key)
        guard fileManager.fileExists(atPath: audio.path) else {
            throw AudioCacheError.audioMissing(audio)
        }
        let meta = StoredMetadata(duration: result.duration, timestamps: result.timestamps)
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL(for: key), options: .atomic)
        return CachedAudio(
            key: key,
            audioURL: audio,
            duration: result.duration,
            timestamps: result.timestamps
        )
    }

    // MARK: - Concurrency control

    /// Tries to claim exclusive render rights for `key`. Returns true
    /// to the leader; false if another render is already running, in
    /// which case the caller should skip (the leader will populate
    /// the cache for everyone). Always pair a true return with
    /// `releaseClaim(_:)` so the slot frees up afterwards.
    func claimRender(_ key: AudioCacheKey) -> Bool {
        guard !inFlightRenders.contains(key) else { return false }
        inFlightRenders.insert(key)
        return true
    }

    func releaseClaim(_ key: AudioCacheKey) {
        inFlightRenders.remove(key)
    }

    /// Block until the global render slot is free, then take it.
    /// FIFO — first-awaited, first-resumed. Pair every call with a
    /// matching `releaseRenderSlot()` (typically via a `defer`).
    /// Prevents two audio renders from competing for synth resources
    /// at the same time.
    func waitForRenderSlot() async {
        if !renderSlotBusy {
            renderSlotBusy = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            renderSlotWaiters.append(cont)
        }
        renderSlotBusy = true
    }

    func releaseRenderSlot() {
        if renderSlotWaiters.isEmpty {
            renderSlotBusy = false
            return
        }
        let next = renderSlotWaiters.removeFirst()
        // Stay busy across handoff so a third caller doesn't race in.
        next.resume()
    }

    /// Removes a single entry (both audio and metadata).
    func evict(_ key: AudioCacheKey) {
        try? fileManager.removeItem(at: audioURL(for: key))
        try? fileManager.removeItem(at: metaURL(for: key))
    }

    /// Wipes the entire cache. Used by Settings → "Clear audio cache"
    /// and by tests.
    func purgeAll() {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    /// Walks the cache directory and evicts least-recently-modified
    /// `.caf` files until the total is within `maxBytes`. The
    /// metadata file beside each evicted audio file goes with it.
    func enforceQuota() {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: .skipsHiddenFiles
        ) else { return }

        // Pair each .caf with its metadata sibling so eviction stays
        // consistent — never leave one half behind.
        let cafs = entries.filter { $0.pathExtension == "caf" }
        var total: Int64 = 0
        var sized: [(url: URL, size: Int64, mtime: Date)] = []
        for url in cafs {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  let size = values.fileSize.map(Int64.init),
                  let mtime = values.contentModificationDate
            else { continue }
            total += size
            sized.append((url, size, mtime))
        }
        guard total > maxBytes else { return }
        // Oldest first.
        sized.sort { $0.mtime < $1.mtime }
        var freed: Int64 = 0
        let toFree = total - maxBytes
        for entry in sized {
            try? fileManager.removeItem(at: entry.url)
            let meta = entry.url.deletingPathExtension().appendingPathExtension("json")
            try? fileManager.removeItem(at: meta)
            freed += entry.size
            if freed >= toFree { break }
        }
        audioCacheLog.debug("Evicted \(freed, privacy: .public) bytes from audio cache (over by \(toFree, privacy: .public))")
    }

    // MARK: - Persisted metadata shape

    private struct StoredMetadata: Codable {
        let duration: TimeInterval
        let timestamps: [AudioTimestamp]
    }
}

enum AudioCacheError: Error, LocalizedError {
    case audioMissing(URL)

    var errorDescription: String? {
        switch self {
        case .audioMissing(let url):
            return "Cache audio file not found at \(url.lastPathComponent)."
        }
    }
}
