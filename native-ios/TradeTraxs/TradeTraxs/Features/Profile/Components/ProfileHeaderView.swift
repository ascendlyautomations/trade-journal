import SwiftUI
import UIKit

struct ProfileHeaderView: View {
    /// Bound directly so avatar / name / username refresh when the content store updates.
    @Bindable var store: ProfileContentStore
    @Bindable var viewModel: ProfileHeaderViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.phase == .loading && store.profile == nil {
                ProfileHeaderSkeleton()
            } else if let profile = store.profile {
                loadedHeader(profile)
            } else {
                errorState
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
            value: store.phase
        )
        .confirmationDialog(
            viewModel.blockConfirmationTitle,
            isPresented: $viewModel.showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(viewModel.blockedByMe ? "Unblock" : "Block", role: viewModel.blockedByMe ? nil : .destructive) {
                Task { await viewModel.confirmBlockToggle() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.blockConfirmationMessage)
        }
        .confirmationDialog(
            "Unfollow @\(store.profile?.username ?? "")?",
            isPresented: $viewModel.pendingUnfollowConfirm,
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                Task { await viewModel.confirmUnfollow() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingUnfollowConfirm = false
            }
        }
    }

    @ViewBuilder
    private func loadedHeader(_ profile: Profile) -> some View {
        let stats = store.stats

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            identityBlock(profile, stats: stats)

            ProfileStatisticsRow(metrics: ProfileDisplay.headerMetrics(from: stats))

            if let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(colors.primaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.bio")
            }

            ProfileActionRow(
                mode: viewModel.actionMode,
                onEdit: viewModel.openEditProfile,
                onShare: viewModel.presentShare,
                onCreateTradeRoom: viewModel.createTradeRoom,
                onViewTradeRoom: viewModel.openTradeRoom,
                onFollow: viewModel.followAction,
                onMessage: viewModel.openMessage,
                onTradeRoom: viewModel.openTradeRoom,
                isMessaging: viewModel.isOpeningMessage,
                canMessage: viewModel.canMessage
            )
        }
        .sheet(isPresented: $viewModel.isSharePresented) {
            if let url = viewModel.shareURL {
                ShareSheet(items: [viewModel.shareText, url])
            } else {
                ShareSheet(items: [viewModel.shareText])
            }
        }
    }

    /// Avatar + name / username / metadata / followers as one identity block.
    @ViewBuilder
    private func identityBlock(_ profile: Profile, stats: ProfileStats?) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            ExperienceAvatar(
                initials: store.initials,
                image: store.avatarImage,
                size: 88
            )
            .accessibilityLabel("\(profile.displayName) profile photo")

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                HStack(spacing: ExperienceSpacing.xxs) {
                    Text(profile.displayName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("profile.displayName")

                    if profile.isCreator {
                        ExperienceTag(title: "Creator", tone: .info)
                    }
                }

                Text("@\(profile.username)")
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(1)
                    .accessibilityIdentifier("profile.username")

                if store.followsYou, !store.isOwner {
                    Text("Follows you")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(colors.tertiaryText)
                        .accessibilityIdentifier("profile.followsYou")
                }

                if let line = ProfileDisplay.metadataLine(for: profile) {
                    Text(line)
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .accessibilityLabel(line.replacingOccurrences(of: " · ", with: ", "))
                        .accessibilityIdentifier("profile.metadata")
                }

                socialSummaryRow(
                    followers: stats?.followerCount ?? 0,
                    following: stats?.followingCount ?? 0
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = "@\(profile.username)"
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
            Button {
                viewModel.presentShare()
            } label: {
                Label("Share Profile", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func socialSummaryRow(followers: Int, following: Int) -> some View {
        HStack(spacing: 4) {
            Button(action: viewModel.openFollowers) {
                Text("\(ProfileDisplay.compactCount(followers)) Followers")
                    .font(.system(.footnote, design: .default).weight(.medium))
                    .foregroundStyle(colors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.followers")

            Text("•")
                .font(.system(.footnote, design: .default).weight(.medium))
                .foregroundStyle(colors.tertiaryText)
                .accessibilityHidden(true)

            Button(action: viewModel.openFollowing) {
                Text("\(ProfileDisplay.compactCount(following)) Following")
                    .font(.system(.footnote, design: .default).weight(.medium))
                    .foregroundStyle(colors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.following")
        }
        .lineLimit(1)
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.socialSummary")
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ExperienceErrorState(
                title: "Couldn’t load profile",
                message: store.errorMessage ?? "Check your connection and try again.",
                retryTitle: "Retry",
                onRetry: { viewModel.retry() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
