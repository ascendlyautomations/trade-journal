import SwiftUI

/// Shared chrome for section containers — loading / empty / error / content slot.
struct ProfileSectionContainerChrome<Content: View>: View {
    let section: ProfileSection
    let state: ProfileSectionLoadState
    var emptyTitle: String? = nil
    var emptyMessage: String? = nil
    var emptyActionTitle: String? = nil
    var emptyAction: (() -> Void)? = nil
    var onRetry: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                loadingBody
            case .empty:
                ExperienceEmptyState(
                    icon: emptyIcon(for: section),
                    title: emptyTitle ?? section.emptyTitle,
                    message: emptyMessage ?? section.emptyMessage,
                    actionTitle: emptyActionTitle,
                    action: emptyAction
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.xl)
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn’t load \(section.title.lowercased())",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: onRetry
                )
                .padding(.vertical, ExperienceSpacing.lg)
            case .loaded:
                content()
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .experiencePadding(.horizontal, .lg)
        .padding(.bottom, ExperienceSpacing.xxl)
    }

    private var loadingBody: some View {
        VStack(spacing: ExperienceSpacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                ExperienceSkeleton(height: 88, cornerRadius: ExperienceRadius.md)
            }
        }
        .padding(.top, ExperienceSpacing.md)
        .accessibilityLabel("Loading \(section.title.lowercased())")
    }

    private func emptyIcon(for section: ProfileSection) -> AppIcon {
        switch section {
        case .trades: return .trades
        case .achievements: return .leaderboard
        case .stats: return .chart
        case .posts, .clips: return .photo
        }
    }
}
