import SwiftUI

/// SkimHN identity, version, source-code link, and a short pitch on
/// the tech stack + privacy stance. Presented as a sheet from the
/// sidebar's About entry.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let githubURL = URL(string: "https://github.com/ctaloi/hn-skim")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    identityBlock
                    openSourceBlock
                    builtWithBlock
                    privacyBlock
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var identityBlock: some View {
        VStack(spacing: 10) {
            iconBadge

            VStack(spacing: 4) {
                Text("SkimHN")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .multilineTextAlignment(.center)
                Text("A calm reader for Hacker News — on-device AI summaries, Liquid Glass UI, zero tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Version \(Self.versionString)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.top, 12)
    }

    private var iconBadge: some View {
        // Mini render of the app icon (three stacked pill bars) so the
        // About screen carries the same visual identity as the home
        // screen tile.
        VStack(alignment: .leading, spacing: 7) {
            Capsule().fill(Theme.accent).frame(width: 72, height: 11)
            Capsule().fill(Color(.label).opacity(0.5)).frame(width: 54, height: 11)
            Capsule().fill(Color(.label).opacity(0.25)).frame(width: 36, height: 11)
        }
        .padding(16)
        .frame(width: 104, height: 104)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
    }

    private var openSourceBlock: some View {
        aboutCard {
            Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("SkimHN is open source. The repository is private for now while the app finds its shape — but you're welcome to follow along.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(Self.githubURL)
            } label: {
                Label {
                    Text(Self.githubURL.host.map { $0 + Self.githubURL.path } ?? Self.githubURL.absoluteString)
                        .font(.footnote.weight(.medium))
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var builtWithBlock: some View {
        aboutCard {
            Label("Built with", systemImage: "hammer")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                techRow(name: "SwiftUI + Liquid Glass", note: "iOS 26 native UI")
                techRow(name: "SwiftData", note: "Local persistence for saved & read state")
                techRow(name: "Apple Foundation Models", note: "On-device LLM for summaries")
                techRow(name: "Algolia HN Search", note: "Search & best-of windows")
                techRow(name: "Firebase HN API", note: "Stories & comments")
            }
        }
    }

    private var privacyBlock: some View {
        aboutCard {
            Label("Privacy", systemImage: "lock.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("No analytics, no tracking, no third-party SDKs. Login (when used) talks directly to news.ycombinator.com; cookies live in the system keychain and never leave the device.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func aboutCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(.secondarySystemBackground),
            in: .rect(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private func techRow(name: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
