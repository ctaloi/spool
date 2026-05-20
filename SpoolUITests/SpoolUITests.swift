import XCTest

/// End-to-end smoke tests. These launch the actual app in the
/// Simulator and drive it via XCUIApplication — the only way to
/// exercise the SwiftUI rendering layer + navigation + system-
/// provided controls (List selection, sheet presentation,
/// NavigationSplitView routing) without standing them up by hand.
///
/// Kept intentionally minimal — three tests, each verifies one
/// high-impact path. The unit tests do the deep coverage; these
/// just confirm the app boots cleanly and the primary surfaces
/// render.
final class SpoolUITests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { false }

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Smoke: the app launches and the navigation surfaces a
    /// recognizable feed title. If this fails, something at the
    /// View Model or NavigationSplitView level is broken before
    /// any user interaction.
    func test_appLaunchesAndShowsAFeedTitle() {
        // The hero title is one of: "Top Stories", "New Stories",
        // "Best Stories", etc. — whichever feed the user last had
        // open (default Top on a fresh install). We just verify
        // *some* feed title is on screen within a reasonable wait.
        let knownTitles = [
            "Top Stories", "New Stories", "Best Stories",
            "Ask HN", "Show HN", "Jobs",
        ]
        let anyTitle = knownTitles
            .map { app.navigationBars.staticTexts[$0] }
            .first { $0.waitForExistence(timeout: 5) }
        XCTAssertNotNil(anyTitle, "no recognized feed title appeared on launch")
    }

    /// Smoke: a recognized toolbar/search element is present on
    /// the main view. Doesn't depend on network — purely about
    /// the UI scaffolding being in place. Either the search field
    /// (categories support it) or the toolbar menu should be
    /// findable.
    func test_mainViewExposesNavigationToolbarElements() {
        // Searchable categories show a search field; other feeds
        // don't. Either way one of these should resolve.
        let searchField = app.searchFields.firstMatch
        let toolbarPicker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Stories' OR label CONTAINS 'Sidebar' OR label CONTAINS 'Spool'")
        ).firstMatch
        let appeared = searchField.waitForExistence(timeout: 5)
            || toolbarPicker.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared,
                      "main view should expose a search field or a recognized toolbar button")
    }

    /// Smoke: VoiceOver-relevant accessibility tree is non-trivial.
    /// A real "I rendered nothing" failure shows up as `app.descendants`
    /// having only the application chrome. We check there's at least
    /// some content depth.
    func test_appAccessibilityTreeHasContent() {
        // Generous timeout — the launch animation may take a moment.
        let mainContent = app.staticTexts.firstMatch
        XCTAssertTrue(mainContent.waitForExistence(timeout: 8),
                      "app should expose at least one accessible text element")
        // Sanity: more than one accessible static text means we're
        // rendering more than just the launch wordmark.
        let allStaticTexts = app.staticTexts.allElementsBoundByIndex
        XCTAssertGreaterThan(allStaticTexts.count, 1,
                             "app should render more than one static text element")
    }
}
