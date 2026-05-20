import SwiftUI

/// Sub-pane of Settings that owns every "what shows up on screen"
/// toggle: thumbnails, hide-read, minimum-comments filter, and
/// per-category visibility. Pushed from the main Settings sheet so
/// the top-level Settings stays tight and doesn't sprawl with feed-
/// customization knobs.
struct DisplaySettingsView: View {
    @AppStorage(SettingsKeys.showThumbnails) private var showThumbnails: Bool = true
    @AppStorage(SettingsKeys.hideReadStories) private var hideReadStories: Bool = false
    @AppStorage(SettingsKeys.minStoryComments) private var minStoryComments: Int = 0
    @AppStorage(SettingsKeys.hiddenFeeds) private var hiddenFeedsRaw: String = ""

    var body: some View {
        Form {
            appearanceSection
            feedSection
            visibleCategoriesSection
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle(isOn: $showThumbnails) {
                Label("Show Thumbnails", systemImage: "photo")
            }
            .tint(Theme.accent)

            Toggle(isOn: $hideReadStories) {
                Label("Hide Read Stories", systemImage: "eye.slash")
            }
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        Section {
            Stepper(value: $minStoryComments, in: 0...100, step: 5) {
                LabeledContent {
                    Text(minStoryComments == 0 ? "Off" : "\(minStoryComments)+")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(minStoryComments)))
                } label: {
                    Label("Minimum Comments", systemImage: "bubble.left.and.bubble.right")
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Feed")
        } footer: {
            Text("Hide drive-by submissions by requiring at least N comments. Doesn't affect Saved or Spool.")
        }
    }

    @ViewBuilder
    private var visibleCategoriesSection: some View {
        Section {
            ForEach(HNStoryFeed.allCases) { feed in
                Toggle(isOn: visibilityBinding(for: feed)) {
                    Label(feed.navigationTitle, systemImage: feed.icon)
                }
                .tint(Theme.accent)
                // Block the last visible toggle from being turned
                // off — at least one category has to stay reachable
                // so the user can navigate back to the feed.
                .disabled(isLastVisible(feed))
            }
        } header: {
            Text("Visible Categories")
        } footer: {
            Text("Hide categories you don't read. Hidden categories disappear from the sidebar and the toolbar feed picker — they're never deleted, just out of the way.")
        }
    }

    // MARK: - Visibility bindings

    private var hiddenSet: Set<HNStoryFeed> {
        HNStoryFeed.hiddenSet(from: hiddenFeedsRaw)
    }

    private func visibilityBinding(for feed: HNStoryFeed) -> Binding<Bool> {
        Binding(
            get: { !hiddenSet.contains(feed) },
            set: { newValue in
                var current = hiddenSet
                if newValue {
                    current.remove(feed)
                } else {
                    current.insert(feed)
                }
                hiddenFeedsRaw = HNStoryFeed.serialize(hidden: current)
            }
        )
    }

    /// True iff `feed` is the only one currently visible. Used to
    /// block the toggle that would zero out the visible-set.
    private func isLastVisible(_ feed: HNStoryFeed) -> Bool {
        let hidden = hiddenSet
        let visibleCount = HNStoryFeed.allCases.filter { !hidden.contains($0) }.count
        return visibleCount == 1 && !hidden.contains(feed)
    }
}
