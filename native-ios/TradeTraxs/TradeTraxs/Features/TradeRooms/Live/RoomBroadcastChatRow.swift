import SwiftUI

struct RoomBroadcastChatRow: View {
    let message: BroadcastChatMessageItem
    let imagePipeline: any ImagePipeline
    @Bindable var coordinator: RoomBroadcastCoordinator
    var isHighlighted: Bool = false
    var onReply: () -> Void = {}
    @Environment(\.themeColors) private var colors

    var body: some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: message.userId)
        let name = profile?.displayName ?? message.displayName
        let username = profile?.username ?? message.displayName
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            RoomBroadcastChatProfileAvatarButton(
                userId: message.userId,
                displayName: name,
                username: username,
                coordinator: coordinator,
                imagePipeline: imagePipeline,
                profile: profile
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoomBroadcastChatProfileNameButton(
                        userId: message.userId,
                        displayName: name,
                        username: username,
                        coordinator: coordinator
                    )
                    Text(BroadcastChatRelativeTime.string(for: message.sentAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(colors.tertiaryText)
                }
                if let reply = message.replyTo {
                    replyPreviewBanner(reply)
                }
                Text(message.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ExperienceSpacing.xxs)
        .padding(.vertical, ExperienceSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .fill(isHighlighted ? colors.accent.opacity(0.14) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onReply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        .accessibilityIdentifier("tradeRooms.broadcast.chat.row.\(message.id)")
    }

    private func replyPreviewBanner(_ reply: BroadcastChatReplyReference) -> some View {
        let replyProfile = coordinator.chatProfileCache.profile(forUserId: reply.userId)
        let replyName = replyProfile?.displayName ?? reply.displayName
        return Button {
            coordinator.scrollToBroadcastChatMessage(id: reply.messageId)
        } label: {
            HStack(alignment: .top, spacing: ExperienceSpacing.xs) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(colors.accent.opacity(0.85))
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(replyName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.accent)
                        .lineLimit(1)
                    Text(reply.textPreview)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(colors.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Reply to \(replyName)")
        .accessibilityHint("Scrolls to original message")
    }
}

enum BroadcastChatRelativeTime {
    static func string(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}