import SwiftUI
import UIKit

/// Compact Discord/iMessage-style room chrome — logo, name, members/info actions.
struct RoomConversationHeaderView: View {
    let room: TradeRoom
    let channelTitle: String?
    let memberCountLabel: String
    let joinButtonTitle: String
    let showsJoinButton: Bool
    let isJoinEnabled: Bool
    let isJoining: Bool
    let onJoinTap: () -> Void
    let onMembersTap: () -> Void
    let onInfoTap: () -> Void
    var inviteShareURL: URL? = nil
    var onCopyInviteLink: (() -> Void)? = nil
    var onCreateFeedPost: (() -> Void)? = nil
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?
    @State private var showsInviteShareSheet = false

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            logo
            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: ExperienceSpacing.xs) {
                    if let channelTitle, !channelTitle.isEmpty {
                        Text(channelTitle)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                    if !memberCountLabel.isEmpty {
                        Text(memberCountLabel)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            HStack(spacing: ExperienceSpacing.xs) {
                if inviteShareURL != nil || onCopyInviteLink != nil || onCreateFeedPost != nil {
                    shareMenu
                }
                headerIconButton(
                    systemName: "person.2",
                    accessibilityLabel: "Members",
                    accessibilityIdentifier: "tradeRooms.conversation.members",
                    action: onMembersTap
                )
                headerIconButton(
                    systemName: "info.circle",
                    accessibilityLabel: "Room info",
                    accessibilityIdentifier: "tradeRooms.conversation.info",
                    action: onInfoTap
                )
                if showsJoinButton {
                    Button(action: onJoinTap) {
                        Group {
                            if isJoining {
                                ProgressView()
                            } else {
                                Text(joinButtonTitle)
                                    .experienceStyle(
                                        .caption,
                                        color: isJoinEnabled ? colors.primaryBackground : colors.secondaryText
                                    )
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 5)
                        .frame(minWidth: 64)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isJoinEnabled ? colors.accent : colors.fillSecondary)
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .disabled(!isJoinEnabled || isJoining)
                    .accessibilityIdentifier("tradeRooms.conversation.join")
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .task(id: room.image?.id) {
            await loadLogo()
        }
        .accessibilityIdentifier("tradeRooms.conversation.header")
        .sheet(isPresented: $showsInviteShareSheet) {
            if let inviteShareURL {
                TradeRoomInviteActivityShareSheet(items: [inviteShareURL])
            }
        }
    }

    private func headerIconButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.primaryText)
                .frame(width: 32, height: 32)
                .background(colors.fillSecondary, in: Circle())
                .experienceTouchTarget()
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var shareMenu: some View {
        Menu {
            if inviteShareURL != nil {
                Button("Share Link") {
                    showsInviteShareSheet = true
                }
            }
            if let onCopyInviteLink {
                Button("Copy Link", action: onCopyInviteLink)
            }
            if let onCreateFeedPost {
                Button("Create Feed Post", action: onCreateFeedPost)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.primaryText)
                .frame(width: 32, height: 32)
                .background(colors.fillSecondary, in: Circle())
                .experienceControlHitTarget()
        }
        .accessibilityLabel("Share room")
        .accessibilityIdentifier("tradeRooms.conversation.share")
    }

    private var logo: some View {
        Group {
            if let logoImage {
                logoImage.resizable().scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
    }

    private func loadLogo() async {
        guard let reference = room.image else {
            logoImage = nil
            return
        }
        if let ui = DemoExploreBundledAvatar.uiImage(for: reference) {
            logoImage = Image(uiImage: ui)
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 96
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }
}
