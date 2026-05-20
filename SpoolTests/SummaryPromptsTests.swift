import Testing
import Foundation
@testable import Spool

/// Tests the user-override resolution layer for SummaryPrompts.
/// Each test runs against a fresh UserDefaults suite so overrides
/// don't leak between cases.
struct SummaryPromptsTests {

    /// Wipe any prompt-related defaults that previous tests (or the
    /// app itself) might have written.
    private func resetOverrides() {
        for key in SummaryPrompts.Key.allCases {
            UserDefaults.standard.removeObject(forKey: key.storageKey)
            UserDefaults.standard.removeObject(forKey: key.forkedFromVersionKey)
        }
    }

    @Test func resolvedReturnsDefaultWhenNoOverride() {
        resetOverrides()
        for key in SummaryPrompts.Key.allCases {
            #expect(SummaryPrompts.resolved(key) == key.defaultText,
                    "no-override should resolve to default for \(key)")
        }
    }

    @Test func resolvedReturnsOverrideWhenSet() {
        resetOverrides()
        UserDefaults.standard.set(
            "You are a pirate. Arr.",
            forKey: SummaryPrompts.Key.article.storageKey
        )
        #expect(SummaryPrompts.resolved(.article) == "You are a pirate. Arr.")
        // Other prompts unaffected.
        #expect(SummaryPrompts.resolved(.comments) == SummaryPrompts.Key.comments.defaultText)
    }

    @Test func setOverridePersistsAndResolves() {
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: "Custom article prompt.")
        #expect(SummaryPrompts.resolved(.article) == "Custom article prompt.")
        #expect(SummaryPrompts.isCustomized(.article))
    }

    @Test func setOverrideWithEmptyClearsStorage() {
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: "Custom.")
        #expect(SummaryPrompts.isCustomized(.article))
        SummaryPrompts.setOverride(.article, text: "")
        #expect(!SummaryPrompts.isCustomized(.article))
        #expect(SummaryPrompts.resolved(.article) == SummaryPrompts.Key.article.defaultText)
    }

    @Test func setOverrideWithDefaultTextClearsStorage() {
        // Writing the default text as an override should clear the
        // override — that way future default changes apply
        // automatically to a user who "reset" by retyping the default.
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: SummaryPrompts.Key.article.defaultText)
        #expect(!SummaryPrompts.isCustomized(.article))
    }

    @Test func setOverrideRecordsForkedFromVersion() {
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: "Custom.")
        let recorded = UserDefaults.standard.integer(forKey: SummaryPrompts.Key.article.forkedFromVersionKey)
        #expect(recorded == SummaryPrompts.Key.article.defaultVersion)
    }

    @Test func isCustomizedReturnsFalseForUntouchedPrompt() {
        resetOverrides()
        #expect(!SummaryPrompts.isCustomized(.article))
    }

    @Test func isCustomizedReturnsFalseForEmptyOverride() {
        resetOverrides()
        UserDefaults.standard.set("", forKey: SummaryPrompts.Key.article.storageKey)
        #expect(!SummaryPrompts.isCustomized(.article))
    }

    @Test func defaultHasMovedOnFalseWhenNoOverride() {
        resetOverrides()
        #expect(!SummaryPrompts.defaultHasMovedOn(.article))
    }

    @Test func defaultHasMovedOnFalseWhenForkedFromCurrentVersion() {
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: "Custom.")
        // setOverride stamps the current defaultVersion, so the user
        // is already on the latest.
        #expect(!SummaryPrompts.defaultHasMovedOn(.article))
    }

    @Test func defaultHasMovedOnTrueWhenForkedFromOlderVersion() {
        resetOverrides()
        UserDefaults.standard.set(
            "Custom prompt from way back.",
            forKey: SummaryPrompts.Key.article.storageKey
        )
        // Simulate a user who customized when defaultVersion was 0.
        UserDefaults.standard.set(0, forKey: SummaryPrompts.Key.article.forkedFromVersionKey)
        #expect(SummaryPrompts.defaultHasMovedOn(.article))
    }

    @Test func convenienceAccessorsUseResolver() {
        resetOverrides()
        SummaryPrompts.setOverride(.article, text: "Custom A.")
        SummaryPrompts.setOverride(.comments, text: "Custom B.")
        #expect(SummaryPrompts.article == "Custom A.")
        #expect(SummaryPrompts.comments == "Custom B.")
    }

    @Test func tierAssignmentSplitsBasicAndAdvanced() {
        let basic = SummaryPrompts.Key.allCases.filter { $0.tier == .basic }
        let advanced = SummaryPrompts.Key.allCases.filter { $0.tier == .advanced }
        #expect(basic.count == 2)
        #expect(Set(basic.map(\.id)) == ["article", "comments"])
        #expect(advanced.count == 5)
    }

    @Test func everyKeyHasNonEmptyDefaultAndDisplay() {
        for key in SummaryPrompts.Key.allCases {
            #expect(!key.defaultText.isEmpty)
            #expect(!key.displayName.isEmpty)
            #expect(!key.subtitle.isEmpty)
        }
    }
}
