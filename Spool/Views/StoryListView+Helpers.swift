import SwiftUI

/// Helpers that used to live as private types at the bottom of
/// StoryListView. Moved here to keep the main file under control —
/// the helpers stand alone and don't reach into StoryListView state.
/// Types are `fileprivate`-equivalent (no other view file should be
/// reaching for them), but Swift's access control across files
/// requires `internal` here — kept under-named so they're clearly
/// StoryListView's tools.

/// Centered ProgressView with a label, used by every loading row
/// inside the main list. Sits inside `statusRow { … }` so it lines
/// up with the empty/error states.
struct StoryListLoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text(text)
                .font(Theme.Typography.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Three-line "show sidebar" button placed in the leading toolbar
/// slot on compact width. Uses `\.dismiss` so the pop goes through
/// the same NavigationStack mechanism the system back chevron would —
/// edge-swipe back to sidebar still works, only the visible glyph
/// changes.
struct StoryListSidebarToggleButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Show Sidebar")
    }
}

/// Applies `.searchable` only when the active feed supports search.
/// SwiftUI doesn't let us conditionally chain modifiers inline without
/// breaking the result-builder type, so wrapping the chain in a
/// `ViewModifier` keeps the existing `listContent` declaration clean.
struct StoryListConditionalSearchable: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    let recentSearches: [String]
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        if isActive {
            content
                .searchable(
                    text: $text,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search HN"
                )
                .searchSuggestions {
                    if text.isEmpty {
                        ForEach(recentSearches, id: \.self) { suggestion in
                            Label(suggestion, systemImage: "clock.arrow.circlepath")
                                .searchCompletion(suggestion)
                        }
                    }
                }
                .onSubmit(of: .search, onSubmit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            content
        }
    }
}
