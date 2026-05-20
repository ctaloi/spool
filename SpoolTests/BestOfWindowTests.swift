import Testing
import Foundation
@testable import Spool

/// BestOfWindow's `sinceTimestamp(relativeTo:)` drives the Algolia
/// search's `created_at_i` lower bound. If we drift here, the "Best
/// of This Week" feed silently returns stories from the wrong span.
struct BestOfWindowTests {

    @Test func everyCaseHasNonEmptyTitle() {
        for window in BestOfWindow.allCases {
            #expect(!window.title.isEmpty)
        }
    }

    @Test func everyCaseHasIconSymbol() {
        for window in BestOfWindow.allCases {
            #expect(!window.icon.isEmpty)
        }
    }

    @Test func todayLowerBoundIsStartOfCurrentDay() {
        // Pick a known mid-day moment, ask `today` for its lower
        // bound — it should be the same calendar day at 00:00 local.
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 14
        components.minute = 30
        let noon = calendar.date(from: components)!

        let lowerBound = BestOfWindow.today.sinceTimestamp(relativeTo: noon)
        let bound = Date(timeIntervalSince1970: TimeInterval(lowerBound))
        let dayOfBound = calendar.component(.day, from: bound)
        #expect(dayOfBound == 15)
        // Should be at start of the day — hour 0.
        #expect(calendar.component(.hour, from: bound) == 0)
        #expect(calendar.component(.minute, from: bound) == 0)
    }

    @Test func weekIsSevenDaysAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerBound = BestOfWindow.week.sinceTimestamp(relativeTo: now)
        let delta = Int(now.timeIntervalSince1970) - lowerBound
        // 7 days = 7 * 86400 = 604800 seconds.
        #expect(delta == 7 * 86_400)
    }

    @Test func monthIsRoughlyAMonthAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerBound = BestOfWindow.month.sinceTimestamp(relativeTo: now)
        let delta = Int(now.timeIntervalSince1970) - lowerBound
        // Calendar months vary (28-31 days). Allow a 5-day fuzz.
        #expect(delta >= 27 * 86_400)
        #expect(delta <= 32 * 86_400)
    }

    @Test func yearIsRoughlyAYearAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerBound = BestOfWindow.year.sinceTimestamp(relativeTo: now)
        let delta = Int(now.timeIntervalSince1970) - lowerBound
        // ~365 days. Allow a 2-day fuzz for leap years.
        #expect(delta >= 363 * 86_400)
        #expect(delta <= 367 * 86_400)
    }

    @Test func ordersFromShortestToLongestWindow() {
        // Today should give the most recent (largest) lower bound,
        // year should give the oldest (smallest).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = BestOfWindow.today.sinceTimestamp(relativeTo: now)
        let week = BestOfWindow.week.sinceTimestamp(relativeTo: now)
        let month = BestOfWindow.month.sinceTimestamp(relativeTo: now)
        let year = BestOfWindow.year.sinceTimestamp(relativeTo: now)
        #expect(today > week)
        #expect(week > month)
        #expect(month > year)
    }
}
