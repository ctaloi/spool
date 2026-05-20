import Testing
import AVFoundation
@testable import Spool

/// Pure-logic tests for SpoolPlayer's voice-quality ranking.
/// Construction of `AVSpeechSynthesisVoice` is system-managed —
/// we can't reliably mint test instances of every quality tier —
/// but the ranking function is pure and exhaustively coverable.
struct SpoolPlayerTests {

    @Test func qualityRankOrderingPutsPremiumOnTop() {
        #expect(SpoolPlayer.qualityRank(.premium) > SpoolPlayer.qualityRank(.enhanced))
        #expect(SpoolPlayer.qualityRank(.enhanced) > SpoolPlayer.qualityRank(.default))
    }

    @Test func qualityRankIsStrictlyMonotonic() {
        let ranks = [
            SpoolPlayer.qualityRank(.default),
            SpoolPlayer.qualityRank(.enhanced),
            SpoolPlayer.qualityRank(.premium),
        ]
        let sorted = ranks.sorted()
        #expect(ranks == sorted, "ranks must already be in ascending order: \(ranks)")
        #expect(Set(ranks).count == 3, "no two quality tiers should share a rank")
    }
}
