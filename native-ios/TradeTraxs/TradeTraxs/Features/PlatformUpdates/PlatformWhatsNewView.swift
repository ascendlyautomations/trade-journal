import SwiftUI

struct PlatformWhatsNewView: View {
    let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var updates: [PlatformUpdateItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ExperienceErrorState(
                    title: "Unable to load updates",
                    message: errorMessage,
                    onRetry: { Task { await load() } }
                )
            } else if updates.isEmpty {
                Text("No updates yet.")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .padding(ExperienceSpacing.md)
            } else {
                List {
                    ForEach(updates) { update in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text(categoryLabel(update.category))
                                .experienceStyle(.caption, color: colors.accent)
                            Text(update.title)
                                .experienceStyle(.headline, color: colors.primaryText)
                            if let publishedAt = update.publishedAt,
                               let date = ISO8601.date(from: publishedAt) {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                            Text(update.body)
                                .experienceStyle(.body, color: colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let url = URL(string: "https://www.tradetraxs.com\(update.href)") {
                                Button("Open in TradeTraxs") {
                                    ExperienceHaptics.play(.selection)
                                    if let destination = appEnvironment.navigation.deepLinkParser.parse(url: url) {
                                        appEnvironment.navigation.coordinator.open(destination)
                                    }
                                }
                                .font(ExperienceTypography.subheadline.weight(.semibold))
                                .foregroundStyle(colors.accent)
                                .padding(.top, ExperienceSpacing.xxs)
                            }
                        }
                        .padding(.vertical, ExperienceSpacing.xs)
                    }
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
            }
        }
        .experienceNavigationTitle("What's New")
        .task {
            await load()
        }
        .accessibilityIdentifier("platform.whatsNew")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let transport = data.supabase.transport else {
            errorMessage = "Unable to load updates. Please try again."
            return
        }
        do {
            updates = try await PlatformWhatsNewClient.fetchPublished(transport: transport)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func categoryLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
