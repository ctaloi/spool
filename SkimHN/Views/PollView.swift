import SwiftUI

/// Renders the options of a Hacker News poll. HN polls are a story-type
/// item whose `parts` field holds the IDs of the option items
/// (`type == "pollopt"`); each option has its own score and is upvotable.
/// We sort by score desc, draw a horizontal bar per option proportional
/// to its share of total votes, and let signed-in users upvote each
/// option using the same VoteButton flow as a story or comment.
struct PollView: View {
    let parts: [Int]
    @Binding var showLogin: Bool

    @State private var options: [HNItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var totalVotes: Int {
        options.reduce(0) { $0 + ($1.score ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Poll", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)

            if let errorMessage, options.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if options.isEmpty && isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if options.isEmpty {
                Text("No options")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    PollOptionRow(
                        option: option,
                        totalVotes: totalVotes,
                        showLogin: $showLogin
                    )
                }

                Text("^[\(totalVotes) total vote](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemBackground),
            in: .rect(cornerRadius: 12, style: .continuous)
        )
        .task(id: parts) { await loadOptions() }
    }

    private func loadOptions() async {
        guard !parts.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await HNAPI.shared.items(ids: parts)
            // HN returns pollopt items with `score` populated. Sort desc.
            options = items.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One labeled bar in the poll. The bar fills proportionally to the
/// option's share of total votes; the option text and vote count read
/// over the bar.
private struct PollOptionRow: View {
    let option: HNItem
    let totalVotes: Int
    @Binding var showLogin: Bool

    @EnvironmentObject private var auth: AuthViewModel

    private var fraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(option.score ?? 0) / Double(totalVotes)
    }

    private var percentLabel: String {
        guard totalVotes > 0 else { return "—" }
        let pct = Int((fraction * 100).rounded())
        return "\(pct)%"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VoteButton(
                itemID: option.id,
                score: option.score ?? 0,
                showLogin: $showLogin
            )
            .environmentObject(auth)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(option.text ?? "(no text)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(percentLabel)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 6)
                        Capsule()
                            .fill(Theme.accent.opacity(0.85))
                            .frame(width: geo.size.width * fraction, height: 6)
                            .animation(.easeOut(duration: 0.4), value: fraction)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}
