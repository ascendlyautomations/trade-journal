import SwiftUI
import UIKit

/// Compact Discord/iMessage-style room chrome — logo, name, members/info actions.
struct RoomConversationHeaderView: View {
    let room: TradeRoom
    let channelTitle: String?
    let memberCountLabel: String
    let joinButtonTitle: String
    let isJoinEnabled: Bool
    let isJoining: Bool
    let onJoinTap: () -> Void
    let onMembersTap: () -> Void
    let onInfoTap: () -> Void
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

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
                    Text(memberCountLabel)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            HStack(spacing: ExperienceSpacing.xs) {
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
                if isJoinEnabled || joinButtonTitle == "Joined" || joinButtonTitle == "Owner" {
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
                            }
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 5)
                        .frame(minWidth: 56)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isJoinEnabled ? colors.accent : colors.fillSecondary)
                        )
                    }
                    .buttonStyle(.plain)
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
        }
        .buttonStyle(.plain)
        .experienceTouchTarget()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
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
