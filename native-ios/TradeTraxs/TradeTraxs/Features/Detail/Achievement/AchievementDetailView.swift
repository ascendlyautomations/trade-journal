import SwiftUI

/// Permanent Achievement detail destination — same hierarchy as Trade Detail.
struct AchievementDetailView: View {
    @State private var viewModel: AchievementDetailViewModel
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(achievementID: AchievementID, data: DataEnvironment) {
        _viewModel = State(
            initialValue: AchievementDetailViewModel(
                achievementID: achievementID,
                achievements: data.achievements,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.achievement == nil:
                ExperienceLoadingSpinner(label: "Loading achievement")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where viewModel.achievement == nil:
                ExperienceErrorState(
                    title: "Couldn't load achievement",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            default:
                content
            }
        }
        .experienceScreenBackground()
        .navigationTitle(viewModel.achievement?.title ?? "Achievement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.loadIfNeeded()
            data.engagementStore.prefetch([.achievement(viewModel.achievementID)])
        }
        .accessibilityIdentifier("detail.achievement.root")
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let achievement = viewModel.achievement {
                        DetailIdentityHeader(
                            initials: viewModel.authorInitials,
                            avatar: viewModel.authorAvatar,
                            displayName: viewModel.authorDisplayName,
                            username: viewModel.authorUsername,
                            dateText: TradeDisplay.dateText(achievement.achievedAt),
                            isOwner: viewModel.isOwner,
                            accessibilityIdentifier: "detail.achievement.identity"
                        )
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.sm)
                        .padding(.bottom, ExperienceSpacing.md)

                        AspectFitMediaView(
                            reference: achievement.image,
                            purpose: .postImage,
                            imagePipeline: imagePipeline,
                            accessibilityIdentifier: "detail.achievement.media",
                            emptyIcon: .leaderboard,
                            allowsFullResolutionViewer: true
                        )

                        achievementBody(achievement, scrollProxy: proxy)
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.md)
                            .padding(.bottom, ExperienceSpacing.xl)
                    }
                }
            }
        }
    }

    private func achievementBody(
        _ achievement: Achievement,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            EngagementBar(
                target: .achievement(achievement.id),
                store: data.engagementStore,
                onCommentTap: {
                    withAnimation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                    }
                }
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(achievement.title)
                    .experienceStyle(.title, color: colors.primaryText)

                HStack(spacing: ExperienceSpacing.xs) {
                    ExperienceTag(title: achievement.tier.rawValue.capitalized, tone: .info)
                    if achievement.isFeatured {
                        ExperienceTag(title: "Featured", tone: .success)
                    }
                    if let value = achievement.value {
                        Text(TradeDisplay.pnlText(value))
                            .experienceStyle(
                                .metric,
                                color: theme.metricColor(
                                    for: NSDecimalNumber(decimal: value.amount).doubleValue
                                )
                            )
                    }
                }

                if let description = achievement.description?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty
                {
                    Text(description)
                        .experienceStyle(.body, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("detail.achievement.description")
                }
            }

            CommentsSectionView(target: .achievement(achievement.id), data: data)
                .id(Self.commentsAnchorID)
        }
    }

    private static let commentsAnchorID = "detail.achievement.comments"
}
