import SwiftUI
import Charts

/// Stats screen pushed from the user profile. Fetches the user's
/// recent submissions + comments via HNUserService and renders three
/// quiet visualizations: lifetime totals, score-per-submission over
/// time, and a 12-week comment-activity heatmap.
struct UserStatsView: View {
    let username: String

    @StateObject private var viewModel = UserStatsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if viewModel.isLoading && viewModel.submissions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    totalsCard
                    scoresCard
                    heatmapCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle("\(username)'s stats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(username: username)
        }
    }

    private var totalsCard: some View {
        statsCard(title: "Lifetime", systemImage: "rosette") {
            HStack(spacing: 18) {
                stat("Karma", viewModel.karma.formatted())
                stat("Submissions", viewModel.submissions.count.formatted())
                stat("Comments", viewModel.comments.count.formatted())
            }
        }
    }

    private var scoresCard: some View {
        statsCard(title: "Submission scores", systemImage: "chart.line.uptrend.xyaxis") {
            if viewModel.submissions.isEmpty {
                Text("No submissions in the last year.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(viewModel.submissions, id: \.id) { sub in
                    LineMark(
                        x: .value("Date", sub.createdAt ?? .now),
                        y: .value("Score", sub.points ?? 0)
                    )
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 140)
            }
        }
    }

    private var heatmapCard: some View {
        statsCard(title: "Comment activity · last 12 weeks", systemImage: "calendar") {
            HeatmapGrid(buckets: viewModel.commentWeekBuckets)
        }
    }

    @ViewBuilder
    private func statsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HeatmapGrid: View {
    /// 84 buckets — 12 weeks × 7 days. Index 0 is 84 days ago, 83 is today.
    let buckets: [Int]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 12)
        let max = max(1, buckets.max() ?? 1)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<min(buckets.count, 84), id: \.self) { i in
                let count = buckets[i]
                let intensity = Double(count) / Double(max)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.accent.opacity(0.12 + intensity * 0.78))
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel("\(count) comments")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
final class UserStatsViewModel: ObservableObject {
    @Published private(set) var karma: Int = 0
    @Published private(set) var submissions: [HNUserSubmission] = []
    @Published private(set) var comments: [HNUserComment] = []
    @Published private(set) var isLoading: Bool = false

    /// 84-bucket array (12 weeks × 7 days) of comment counts per day,
    /// oldest first, ending today.
    var commentWeekBuckets: [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var buckets = Array(repeating: 0, count: 84)
        for c in comments {
            guard let date = c.createdAt else { continue }
            let day = calendar.startOfDay(for: date)
            let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 999
            if daysAgo >= 0 && daysAgo < 84 {
                buckets[83 - daysAgo] += 1
            }
        }
        return buckets
    }

    func load(username: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let userTask = HNUserService.shared.user(id: username)
            async let subsTask = HNUserService.shared.submissions(by: username, page: 0)
            async let commsTask = HNUserService.shared.comments(by: username, page: 0)
            let (user, subs, comms) = try await (userTask, subsTask, commsTask)
            self.karma = user.karma ?? 0
            self.submissions = subs.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            self.comments = comms
        } catch {
            // Silent — empty cards will indicate failure.
        }
    }
}
