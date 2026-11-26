import SwiftUI
import UIKit

struct ConversationRowView: View {
    let item: DirectMessageInboxItem
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors
    @State private var avatarImage: Image?

    var body: some View {
        HStack(alignment: .center, spacing: MessagesInboxLayout.rowHorizontalSpacing) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xs) {
                    HStack(spacing: ExperienceSpacing.xxs) {
                        if item.conversation.isGroup {
                            ExperienceIcon(icon: .rooms, size: .sm, color: colors.accent)
                                .alignmentGuide(.firstTextBaseline) { dimensions in
                                    dimensions[.bottom] - 1
                                }
                                .accessibilityHidden(true)
                        }
                        Text(item.displayName)
                            .experienceStyle(item.unreadCount > 0 ? .headline : .body, color: colors.primaryText)
                            .lineLimit(1)
                    }
                    if item.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(colors.tertiaryText)
                            .accessibilityLabel("Muted")
                    }
                    Spacer(minLength: 4)
                    Text(MessagesInboxSupport.relativeTimestamp(item.timestamp))
                        .experienceStyle(.caption, color: item.unreadCount > 0 ? colors.accent : colors.tertiaryText)
                        .lineLimit(1)
                }
                HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        if showsUsernameSubtitle, let username = item.username {
                            Text(username)
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .lineLimit(1)
                        }
                        previewLine
                    }
                    Spacer(minLength: 4)
                    trailingBadges
                }
            }
        }
        .padding(.vertical, MessagesInboxLayout.rowVerticalPadding)
        .contentShape(Rectangle())
        .task(id: item.peer?.avatar?.id ?? item.conversation.avatar?.id) {
            guard !item.conversation.isGroup else { return }
            await loadAvatar()
        }
        .experienceAccessibility(
            label: item.preview.isEmpty ? item.displayName : "\(item.displayName). \(item.preview)",
            hint: item.unreadCount > 0 ? "\(item.unreadCount) unread" : nil,
            identifier: "messages.conversation.\(item.id.rawValue)"
        )
    }

    private var showsUsernameSubtitle: Bool {
        !showsCompactPreview
    }

    private var showsCompactPreview: Bool {
        if item.isTyping { return true }
        let trimmed = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != "No messages yet"
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if item.conversation.isGroup {
                GroupConversationAvatarView(
                    avatar: item.conversation.avatar,
                    imagePipeline: imagePipeline,
                    size: MessagesInboxLayout.avatarSide
                )
            } else {
                ExperienceAvatar(
                    initials: ProfileDisplay.initials(
                        displayName: item.displayName,
                        username: item.peer?.username ?? ""
                    ),
                    image: avatarImage,
                    size: MessagesInboxLayout.avatarSide
                )
            }
            if item.isOnline, !item.conversation.isGroup {
                Circle()
                    .fill(colors.success)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(colors.backgroundPrimary, lineWidth: 2))
                    .offset(x: 1, y: 1)
                    .accessibilityLabel("Online")
            }
        }
    }

    @ViewBuilder
    private var previewLine: some View {
        if item.isTyping {
            Text("Typing…")
                .experienceStyle(.subheadline, color: colors.accent)
                .lineLimit(1)
        } else if !item.preview.isEmpty {
            HStack(spacing: 4) {
                if item.showsReadReceipt {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                        .accessibilityLabel("Read")
                }
                Text(item.preview)
                    .experienceStyle(
                        item.unreadCount > 0 ? .subheadline : .footnote,
                        color: item.unreadCount > 0 ? colors.primaryText : colors.secondaryText
                    )
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var trailingBadges: some View {
        if item.unreadCount > 0 {
            Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(colors.onAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(colors.accent, in: Capsule())
                .accessibilityLabel("\(item.unreadCount) unread")
        }
    }

    private func loadAvatar() async {
        guard let reference = item.peer?.avatar ?? item.conversation.avatar else {
            avatarImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 128
                )
            )
            if let ui = UIImage(data: data) {
                avatarImage = Image(uiImage: ui)
            }
        } catch {
            avatarImage = nil
        }
    }
}