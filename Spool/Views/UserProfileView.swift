import SwiftUI
import SwiftData

struct UserProfileView: View {
    let username: String

    @StateObject private var viewModel = UserProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var followed: [FollowedUser]
    @State private var tab: Tab = .submissions
    @State private var openStory: HNItem?

    enum Tab: Hashable { case submissions, comments }

    private var isFollowed: Bool {
        followed.contains { $0.username == username }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(username)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            toggleFollow()
                        } label: {
                            Label(
                                isFollowed ? "Following" : "Follow",
                                systemImage: isFollowed ? "checkmark.circle.fill" : "plus.circle"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isFollowed ? Theme.accent : .secondary)
                        }
                        .accessibilityLabel(isFollowed ? "Unfollow \(username)" : "Follow \(username)")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(item: $openStory) { item in
                    StoryDetailView(story: item)
                        .id(item.id)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        NavigationLink {
                            UserStatsView(username: username)
                        } label: {
                            HStack(spacing: 4) {
                                Text(username)
                                    .font(.headline)
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View stats for \(username)")
                    }
                }
        }
        .onAppear {
            Task { await viewModel.load(username: username) }
        }
    }

    private func toggleFollow() {
        if let existing = followed.first(where: { $0.username == username }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FollowedUser(username: username))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage,
           viewModel.user == nil && viewModel.submissions.isEmpty && viewModel.comments.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load profile", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.load(username: username) }
                }
                .buttonStyle(.bordered)
            }
        } else {
            List {
                profileHeaderSection
                tabPickerSection
                activitySection
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(username)
                            .font(.title3.weight(.bold))
                        if let joined = viewModel.user?.joinedDate {
                            Text("Joined \(joined, format: .dateTime.month().year())")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let karma = viewModel.user?.karma {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(karma)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                            Text("karma")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let about = viewModel.user?.about,
                   !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HTMLText(html: about)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabPickerSection: some View {
        Section {
            Picker("Activity", selection: $tab) {
                Text("Submissions (\(viewModel.submissions.count))")
                    .tag(Tab.submissions)
                Text("Comments (\(viewModel.comments.count))")
                    .tag(Tab.comments)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Activity

    @ViewBuilder
    private var activitySection: some View {
        if viewModel.isLoading && viewModel.submissions.isEmpty && viewModel.comments.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            }
        } else {
            switch tab {
            case .submissions: submissionsSection
            case .comments:    commentsSection
            }
        }
    }

    @ViewBuilder
    private var submissionsSection: some View {
        if viewModel.submissions.isEmpty {
            Section {
                Text("No submissions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(viewModel.submissions) { item in
                    Button {
                        openStory = item.asHNItem
                    } label: {
                        SubmissionRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if viewModel.comments.isEmpty {
            Section {
                Text("No comments.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(viewModel.comments) { c in
                    Button {
                        guard let storyID = c.storyID else { return }
                        let placeholder = HNItem(
                            id: storyID, type: "story", by: nil, time: nil,
                            text: nil, url: nil, title: c.storyTitle, score: nil,
                            descendants: nil, kids: nil, parent: nil,
                            deleted: nil, dead: nil, parts: nil
                        )
                        openStory = placeholder
                    } label: {
                        CommentRow(comment: c)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Rows

private struct SubmissionRow: View {
    let item: HNUserSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? "(no title)")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
            HStack(spacing: 0) {
                if let points = item.points {
                    Text("^[\(points) point](inflect: true)")
                        .monospacedDigit()
                    sep
                }
                if let n = item.numComments {
                    Text("^[\(n) comment](inflect: true)")
                        .monospacedDigit()
                    sep
                }
                if let date = item.createdAt {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var sep: some View {
        Text(verbatim: "  ·  ")
            .foregroundStyle(.tertiary)
    }
}

private struct CommentRow: View {
    let comment: HNUserComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = comment.storyTitle {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            HTMLText(html: comment.commentText)
                .lineLimit(8)
            if let date = comment.createdAt {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
