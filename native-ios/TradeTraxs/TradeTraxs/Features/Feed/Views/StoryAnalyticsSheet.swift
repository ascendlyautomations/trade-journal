import SwiftUI

struct StoryAnalyticsSheet: View {
    @State private var viewModel: StoryAnalyticsViewModel
    let imagePipeline: any ImagePipeline
    let detailCache: DetailPresentationCache
    let onClose: () -> Void
    let onOpenProfile: (ProfileID) -> Void

    @Environment(\.themeColors) private var colors

    init(
        storyID: StoryID,
        feed: any FeedRepository,
        imagePipeline: any ImagePipeline,
        detailCache: DetailPresentationCache,
        onClose: @escaping () -> Void,
        onOpenProfile: @escaping (ProfileID) -> Void
    ) {
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
        self.onClose = onClose
        self.onOpenProfile = onOpenProfile
        _viewModel = State(
            initialValue: StoryAnalyticsViewModel(
                storyID: storyID,
                feed: feed,
                detailCache: detailCache
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ExperienceErrorState(title: "Couldn't load analytics", message: message) {
                        viewModel.reload()
                        Task { await viewModel.loadIfNeeded() }
                    }
                case .loaded(let insights):
                    loadedContent(insights)
                }
            }
            .experienceScreenBackground()
            .navigationTitle("Story Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .experienceSheetChrome(keyboardDoneToolbar: false)
        .task { await viewModel.loadIfNeeded() }
        .accessibilityIdentifier("feed.story.analyticsSheet")
    }

    @ViewBuilder
    private func loadedContent(_ insights: StoryInsights) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                metricsRow(insights)
                ExperienceDivider()
                viewersSection(insights)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
        }
    }

    private func metricsRow(_ insights: StoryInsights) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            metricCard(title: "Viewers", value: insights.viewCount)
            metricCard(title: "Likes", value: insights.likeCount)
            metricCard(title: "Replies", value: insights.replyCount)
        }
    }

    private func metricCard(title: String, value: Int) -> some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.primaryText)
            Text(title)
                .font(.footnote)
                .foregroundStyle(colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func viewersSection(_ insights: StoryInsights) -> some View {
        Text("Viewers")
            .font(.headline.weight(.semibold))
            .foregroundStyle(colors.primaryText)
            .accessibilityAddTraits(.isHeader)

        if insights.viewers.isEmpty {
            Text("No viewers yet")
                .font(.subheadline)
                .foregroundStyle(colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.md)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(insights.viewers) { viewer in
                    viewerRow(viewer)
                    if viewer.id != insights.viewers.last?.id {
                        ExperienceDivider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func resolvedProfile(for viewer: StoryInsightsViewer) -> Profile {
        detailCache.profile(id: viewer.id)
            ?? FollowListFixtures.profile(id: viewer.id)
            ?? viewer.profileStub
    }

    private func viewerRow(_ viewer: StoryInsightsViewer) -> some View {
        let profile = resolvedProfile(for: viewer)

        return HStack(spacing: ExperienceSpacing.md) {
            Button {
                openViewerProfile(viewer.id)
            } label: {
                FollowListAvatarView(
                    profile: profile,
                    imagePipeline: imagePipeline,
                    size: 44,
                    debugSurface: "storyAnalytics"
                )
                .accessibilityLabel("Open \(viewer.displayName) profile")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed.story.analytics.viewer.avatar.\(viewer.id.rawValue)")

            Button {
                openViewerProfile(viewer.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewer.displayName)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text("@\(viewer.username)")
                        .font(.footnote)
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed.story.analytics.viewer.username.\(viewer.id.rawValue)")

            HStack(spacing: ExperienceSpacing.xs) {
                if viewer.replied {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .accessibilityLabel("Replied to your story")
                }
                if viewer.liked {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .accessibilityLabel("Liked your story")
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.sm)
    }

    private func openViewerProfile(_ profileID: ProfileID) {
        ExperienceHaptics.play(.selection)
        onOpenProfile(profileID)
    }
}