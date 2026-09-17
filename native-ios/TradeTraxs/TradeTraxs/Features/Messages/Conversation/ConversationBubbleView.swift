import SwiftUI
import UIKit

struct ConversationBubbleView: View {
    let item: ConversationBubbleItem
    let peerProfile: Profile?
    let imagePipeline: any ImagePipeline
    var viewerProfileID: ProfileID? = nil
    var sharedTrade: Trade? = nil
    var sharedPost: Post? = nil
    var sharedPostAuthor: Profile? = nil
    var sharedReel: Reel? = nil
    var sharedReelAuthor: Profile? = nil
    var sharedAchievement: Achievement? = nil
    var sharedAchievementAuthor: Profile? = nil
    var isSharedContentUnavailable: Bool = false
    var reactionConfiguration: MessageReactionConfiguration? = nil
    var onLongPressForActionMenu: (() -> Void)? = nil
    var canDelete: Bool = false
    var deleteMenuTitle: String = "Delete"
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSharedTradeTap: ((TradeID) -> Void)? = nil
    var onSharedContentTap: ((SharedContentReference) -> Void)? = nil
    var onSharedStoryTap: ((StoryShareMessageSupport.Payload) -> Void)? = nil
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    /// Trade Rooms — tap sender avatar to open public profile (uses message sender ID).
    var onSenderAvatarTap: ((ProfileID) -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .bottom, spacing: ConversationBubbleLayout.avatarToContentSpacing) {
            if isSelectionMode {
                selectionCheckbox
            }
            if item.isOutgoing {
                Spacer(minLength: ConversationBubbleLayout.oppositeGutterMin)
                bubbleColumn(alignment: .trailing)
                    .frame(maxWidth: contentColumnMaxWidth, alignment: .trailing)
            } else {
                avatarSlot
                bubbleColumn(alignment: .leading)
                    .frame(maxWidth: contentColumnMaxWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: item.isOutgoing ? .trailing : .leading)
        .padding(.horizontal, ConversationBubbleLayout.rowHorizontalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelectionMode else { return }
            onToggleSelection?()
        }
        .accessibilityIdentifier(
            item.isOutgoing ? "conversation.bubble.outgoing" : "conversation.bubble.incoming"
        )
        .onLongPressGesture(minimumDuration: 0.38, maximumDistance: 12) {
            guard !isSelectionMode, showsActionMenu else { return }
            ExperienceHaptics.play(.impactLight)
            onLongPressForActionMenu?()
        }
    }

    private var showsActionMenu: Bool {
        reactionInteractionsEnabled
            || canDelete
            || onReport != nil
            || (item.sendState == .failed && onRetry != nil)
            || copyableText != nil
    }

    private var copyableText: String? {
        guard let text = item.text, !text.isEmpty, item.message.kind != .tradeShare else { return nil }
        return text
    }

    private var resolvedAuthor: Profile? {
        item.authorProfile ?? peerProfile
    }

    @ViewBuilder
    private var avatarSlot: some View {
        Group {
            if item.showsAvatar {
                if let onSenderAvatarTap {
                    Button {
                        onSenderAvatarTap(item.message.senderProfileID)
                    } label: {
                        ConversationPeerAvatarView(
                            profile: resolvedAuthor,
                            imagePipeline: imagePipeline,
                            size: ConversationBubbleLayout.avatarColumnWidth
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View profile")
                    .accessibilityIdentifier("conversation.bubble.senderAvatar")
                } else {
                    ConversationPeerAvatarView(
                        profile: resolvedAuthor,
                        imagePipeline: imagePipeline,
                        size: ConversationBubbleLayout.avatarColumnWidth
                    )
                }
            } else {
                Color.clear
            }
        }
        .frame(
            width: ConversationBubbleLayout.avatarColumnWidth,
            height: ConversationBubbleLayout.avatarColumnWidth
        )
    }

    private func bubbleColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if item.showsAuthorName, !item.isOutgoing {
                HStack(spacing: ExperienceSpacing.xxs) {
                    Text(ConversationThreadSupport.senderDisplayName(for: resolvedAuthor))
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                    if item.showsOwnerBadge || !item.authorTags.isEmpty {
                        RoomMemberTagChipsView(
                            tags: item.authorTags,
                            showsOwnerBadge: item.showsOwnerBadge,
                            limit: 3
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            bubbleContent
            if item.showsTimestamp || item.sendState != .sent {
                timestampRow
            }
        }
    }

    private var contentColumnMaxWidth: CGFloat {
        if item.isOutgoing {
            return ConversationBubbleLayout.outgoingContentColumnMax(isSelectionMode: isSelectionMode)
        }
        return ConversationBubbleLayout.incomingContentColumnMax(isSelectionMode: isSelectionMode)
    }

    @ViewBuilder
    private var timestampRow: some View {
        HStack(spacing: 6) {
            if item.sendState == .sending {
                Text("Sending…")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            } else if item.sendState == .failed {
                Button {
                    onRetry?()
                } label: {
                    Text("Failed · Tap to retry")
                        .experienceStyle(.caption2, color: colors.warning)
                }
                .buttonStyle(.plain)
            } else if item.showsTimestamp {
                Text(ConversationThreadSupport.timeLabel(item.message.createdAt))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Group {
            if item.message.kind == .tradeShare,
               let tradeID = item.message.attachments.first?.tradeID
            {
                tradeShareBubble(tradeID: tradeID)
            } else if item.message.kind == .feedPostShare || item.message.kind == .profilePostShare {
                sharedPostBubble
            } else if item.message.kind == .reelShare {
                sharedReelBubble
            } else if item.message.kind == .achievementPostShare {
                sharedAchievementBubble
            } else if item.message.kind == .storyReply,
                      let payload = StoryReplyMessageSupport.decode(from: item.message.body)
            {
                storyReplyBubble(payload: payload)
            } else if item.message.kind == .storyShare,
                      let payload = StoryShareMessageSupport.decode(from: item.message.body)
            {
                storyShareBubble(payload: payload)
            } else if item.message.kind != .storyReply,
                      let payload = StoryShareMessageSupport.decode(from: item.message.body)
            {
                storyShareBubble(payload: payload)
            } else if let reference = item.voiceReference {
                voiceBubble(reference: reference, duration: item.voiceDuration)
            } else if let reference = item.imageReference, item.message.kind != .tradeShare {
                imageBubble(reference: reference)
            } else if let text = item.text {
                textBubble(text: text)
            } else if showsInlineReactions {
                reactionsOnlyBubble
            }
        }
        .opacity(item.sendState == .sending ? 0.72 : 1)
        .messageReactionInteractions(
            isEnabled: reactionInteractionsEnabled,
            onDoubleTapLike: { reactionConfiguration?.onToggle(MessageReactionSemantics.doubleTapLikeEmoji) }
        )
    }

    private var reactionInteractionsEnabled: Bool {
        !isSelectionMode
            && item.sendState == .sent
            && reactionConfiguration?.isEnabled == true
    }

    private var showsInlineReactions: Bool {
        reactionConfiguration?.showsStrip == true
    }

    private func textBubble(text: String) -> some View {
        let alignment: HorizontalAlignment = item.isOutgoing ? .trailing : .leading
        return VStack(alignment: alignment, spacing: 0) {
            ConversationMessageTextLayout(
                maxWidth: bubbleMaxWidth,
                horizontalAlignment: alignment
            ) {
                Text(text)
                    .experienceStyle(
                        .body,
                        color: item.isOutgoing ? colors.onAccent : colors.primaryText
                    )
                    .multilineTextAlignment(item.isOutgoing ? .trailing : .leading)
            }
            reactionChipsOnly(topPadding: 6)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, reactionBottomPadding)
        .background(
            item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private func voiceBubble(reference: MediaReference, duration: TimeInterval?) -> some View {
        VoiceMessageBubbleView(
            messageID: item.id,
            audioReference: reference,
            durationSeconds: duration,
            isOutgoing: item.isOutgoing
        )
    }

    private func storyReplyBubble(payload: StoryReplyMessageSupport.Payload) -> some View {
        StoryReplyMessageBubbleView(
            payload: payload,
            viewerProfileID: viewerProfileID,
            isOutgoing: item.isOutgoing,
            imagePipeline: imagePipeline
        )
    }

    private func storyShareBubble(payload: StoryShareMessageSupport.Payload) -> some View {
        Group {
            if isSelectionMode {
                storyShareBubbleContent(payload: payload)
            } else {
                Button {
                    ExperienceHaptics.play(.selection)
                    onSharedStoryTap?(payload)
                } label: {
                    storyShareBubbleContent(payload: payload)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("conversation.bubble.storyShare")
    }

    private func storyShareBubbleContent(payload: StoryShareMessageSupport.Payload) -> some View {
        StoryShareMessageBubbleView(
            payload: payload,
            isOutgoing: item.isOutgoing,
            imagePipeline: imagePipeline
        )
    }

    private func imageBubble(reference: MediaReference) -> some View {
        AspectFitMediaView(
            reference: reference,
            purpose: .tradeScreenshot,
            imagePipeline: imagePipeline,
            accessibilityIdentifier: "conversation.bubble.image",
            emptyIcon: .photo,
            allowsFullResolutionViewer: true
        )
        .frame(maxWidth: 240)
        .overlay(alignment: .bottomLeading) {
            reactionChipsOnly(topPadding: 0)
                .padding(6)
        }
        .frame(maxWidth: 240, alignment: item.isOutgoing ? .trailing : .leading)
        .clipShape(
            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private func tradeShareBubble(tradeID: TradeID) -> some View {
        Group {
            if isSelectionMode {
                tradeShareBubbleContent(tradeID: tradeID)
            } else {
                Button {
                    ExperienceHaptics.play(.selection)
                    onSharedTradeTap?(tradeID)
                } label: {
                    tradeShareBubbleContent(tradeID: tradeID)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("conversation.bubble.trade")
    }

    private func tradeShareBubbleContent(tradeID: TradeID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SharedTradeMessageCard(
                trade: sharedTrade,
                tradeID: tradeID,
                imagePipeline: imagePipeline,
                isOutgoing: item.isOutgoing,
                includesBackground: false
            )
            reactionChipsOnly(topPadding: 6)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, reactionBottomPadding)
        .frame(maxWidth: tradeBubbleMaxWidth, alignment: .leading)
        .background(
            item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private var sharedPostBubble: some View {
        sharedContentBubble {
            if isSharedContentUnavailable {
                SharedContentUnavailableCard(title: "Shared a post", isOutgoing: item.isOutgoing, includesBackground: false)
            } else if let post = sharedPost, let tradeID = post.linkedTradeID, item.message.kind == .feedPostShare {
                SharedTradeMessageCard(
                    trade: sharedTrade,
                    tradeID: tradeID,
                    imagePipeline: imagePipeline,
                    isOutgoing: item.isOutgoing,
                    includesBackground: false
                )
            } else {
                SharedPostMessageCard(
                    post: sharedPost,
                    author: sharedPostAuthor,
                    imagePipeline: imagePipeline,
                    isOutgoing: item.isOutgoing,
                    includesBackground: false,
                    headerTitle: item.message.kind == .profilePostShare ? "Shared a post" : "Shared a post"
                )
            }
        }
    }

    private var sharedReelBubble: some View {
        sharedContentBubble {
            if isSharedContentUnavailable {
                SharedContentUnavailableCard(title: "Shared a clip", isOutgoing: item.isOutgoing, includesBackground: false)
            } else {
                SharedReelMessageCard(
                    reel: sharedReel,
                    author: sharedReelAuthor,
                    imagePipeline: imagePipeline,
                    isOutgoing: item.isOutgoing,
                    includesBackground: false
                )
            }
        }
    }

    private var sharedAchievementBubble: some View {
        sharedContentBubble {
            if isSharedContentUnavailable {
                SharedContentUnavailableCard(title: "Shared an achievement", isOutgoing: item.isOutgoing, includesBackground: false)
            } else {
                SharedAchievementMessageCard(
                    achievement: sharedAchievement,
                    author: sharedAchievementAuthor,
                    imagePipeline: imagePipeline,
                    isOutgoing: item.isOutgoing,
                    includesBackground: false
                )
            }
        }
    }

    @ViewBuilder
    private func sharedContentBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Group {
            if isSelectionMode {
                sharedContentBubbleContent(content: content)
            } else if let reference = item.message.sharedContent {
                Button {
                    ExperienceHaptics.play(.selection)
                    onSharedContentTap?(reference)
                } label: {
                    sharedContentBubbleContent(content: content)
                }
                .buttonStyle(.plain)
            } else {
                sharedContentBubbleContent(content: content)
            }
        }
    }

    private func sharedContentBubbleContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            reactionChipsOnly(topPadding: 6)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, reactionBottomPadding)
        .frame(maxWidth: tradeBubbleMaxWidth, alignment: .leading)
        .background(
            item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private var reactionsOnlyBubble: some View {
        Color.clear
            .frame(width: 44, height: 32)
            .padding(.horizontal, ExperienceSpacing.sm + 2)
            .padding(.vertical, ExperienceSpacing.xs)
            .background(
                item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
            )
    }

    @ViewBuilder
    private func reactionChipsOnly(topPadding: CGFloat) -> some View {
        if let reactionConfiguration, !reactionConfiguration.summaries.isEmpty {
            MessageReactionStrip(
                summaries: reactionConfiguration.summaries,
                isOutgoing: item.isOutgoing,
                isEnabled: reactionConfiguration.isEnabled,
                onToggle: reactionConfiguration.onToggle
            )
            .frame(maxWidth: bubbleMaxWidth, alignment: item.isOutgoing ? .trailing : .leading)
            .padding(.top, topPadding)
        }
    }

    private var reactionBottomPadding: CGFloat {
        guard let reactionConfiguration else { return ExperienceSpacing.sm }
        if !reactionConfiguration.summaries.isEmpty {
            return ExperienceSpacing.xs + 2
        }
        return ExperienceSpacing.sm
    }

    /// Maximum bubble width (~72% of screen). Short messages stay intrinsic; long text wraps at this cap.
    private var bubbleMaxWidth: CGFloat {
        min(ConversationBubbleLayout.viewportWidth * 0.72, contentColumnMaxWidth)
    }

    private var tradeBubbleMaxWidth: CGFloat {
        min(280, contentColumnMaxWidth)
    }

    private var selectionCheckbox: some View {
        Button {
            onToggleSelection?()
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? colors.accent : colors.tertiaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("conversation.bubble.selection")
    }
}

/// Stable incoming/outgoing row grid for DMs and Trade Rooms (avatar column + content column).
private enum ConversationBubbleLayout {
    static let avatarColumnWidth: CGFloat = 28
    static let rowHorizontalPadding = ExperienceSpacing.md
    static let avatarToContentSpacing = ExperienceSpacing.xs
    static let oppositeGutterMin: CGFloat = 48
    private static let selectionColumnWidth: CGFloat = 28

    static var viewportWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    static func incomingContentColumnMax(isSelectionMode: Bool) -> CGFloat {
        let selection = isSelectionMode ? selectionColumnWidth + avatarToContentSpacing : 0
        return viewportWidth
            - (2 * rowHorizontalPadding)
            - selection
            - avatarColumnWidth
            - avatarToContentSpacing
            - oppositeGutterMin
    }

    static func outgoingContentColumnMax(isSelectionMode: Bool) -> CGFloat {
        let selection = isSelectionMode ? selectionColumnWidth + avatarToContentSpacing : 0
        return viewportWidth
            - (2 * rowHorizontalPadding)
            - selection
            - oppositeGutterMin
    }
}

private struct ConversationPeerAvatarView: View {
    let profile: Profile?
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 28

    @State private var image: Image?

    var body: some View {
        ExperienceAvatar(
            initials: ProfileDisplay.initials(
                displayName: profile?.displayName ?? "",
                username: profile?.username ?? ""
            ),
            image: image,
            size: size
        )
        .task(id: profile?.id) {
            await load()
        }
    }

    private func load() async {
        guard let reference = profile?.avatar else {
            image = nil
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
                image = Image(uiImage: ui)
            }
        } catch {
            image = nil
        }
    }
}

struct ConversationDaySeparatorView: View {
    let title: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(title)
            .experienceStyle(.caption, color: colors.tertiaryText)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, 4)
            .background(colors.fillSecondary.opacity(0.85), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, ExperienceSpacing.sm)
            .accessibilityIdentifier("conversation.daySeparator")
    }
}
