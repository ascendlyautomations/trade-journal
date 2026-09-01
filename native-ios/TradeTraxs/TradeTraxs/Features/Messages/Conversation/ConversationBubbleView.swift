import SwiftUI
import UIKit

struct ConversationBubbleView: View {
    let item: ConversationBubbleItem
    let peerProfile: Profile?
    let imagePipeline: any ImagePipeline
    var sharedTrade: Trade? = nil
    var reactionConfiguration: MessageReactionConfiguration? = nil
    var onRetry: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.xs) {
            if item.isOutgoing {
                Spacer(minLength: 48)
                bubbleColumn(alignment: .trailing)
            } else {
                avatarSlot
                bubbleColumn(alignment: .leading)
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier(
            item.isOutgoing ? "conversation.bubble.outgoing" : "conversation.bubble.incoming"
        )
    }

    private var resolvedAuthor: Profile? {
        item.authorProfile ?? peerProfile
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if item.showsAvatar {
            ConversationPeerAvatarView(
                profile: resolvedAuthor,
                imagePipeline: imagePipeline,
                size: 28
            )
        } else {
            Color.clear.frame(width: 28, height: 28)
        }
    }

    private func bubbleColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if item.showsAuthorName, !item.isOutgoing, let name = resolvedAuthor?.displayName {
                Text(name)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .padding(.leading, 4)
            }
            bubbleContent
            if item.showsTimestamp || item.sendState != .sent {
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
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: item.isOutgoing ? .trailing : .leading, spacing: ExperienceSpacing.xs) {
            if item.message.kind == .tradeShare,
               let tradeID = item.message.attachments.first?.tradeID
            {
                tradeShareBubble(tradeID: tradeID)
            } else if let reference = item.imageReference, item.message.kind != .tradeShare {
                imageBubble(reference: reference)
            } else if let text = item.text {
                textBubble(text: text)
            } else if showsInlineReactions {
                reactionsOnlyBubble
            }
        }
        .opacity(item.sendState == .sending ? 0.72 : 1)
        .contextMenu {
            bubbleContextMenu
        }
    }

    @ViewBuilder
    private var bubbleContextMenu: some View {
        if let text = item.text, !text.isEmpty, item.message.kind != .tradeShare {
            Button {
                UIPasteboard.general.string = text
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        if let reactionConfiguration, reactionConfiguration.isEnabled {
            Menu("React") {
                ForEach(reactionConfiguration.supportedEmojis, id: \.self) { emoji in
                    Button(emoji) {
                        reactionConfiguration.onToggle(emoji)
                    }
                }
            }
        }
        if item.sendState == .failed, let onRetry {
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
    }

    private var showsInlineReactions: Bool {
        reactionConfiguration?.showsStrip == true
    }

    private func textBubble(text: String) -> some View {
        VStack(alignment: item.isOutgoing ? .trailing : .leading, spacing: 0) {
            Text(text)
                .experienceStyle(
                    .body,
                    color: item.isOutgoing ? colors.onAccent : colors.primaryText
                )
                .multilineTextAlignment(item.isOutgoing ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            inlineReactionStrip(topPadding: 6)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, reactionBottomPadding)
        .frame(maxWidth: bubbleMaxWidth, alignment: item.isOutgoing ? .trailing : .leading)
        .background(
            item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private func imageBubble(reference: MediaReference) -> some View {
        ZStack(alignment: .bottomLeading) {
            AspectFitMediaView(
                reference: reference,
                purpose: .tradeScreenshot,
                imagePipeline: imagePipeline,
                accessibilityIdentifier: "conversation.bubble.image",
                emptyIcon: .photo,
                allowsFullResolutionViewer: true
            )
            .frame(maxWidth: 240)

            if showsInlineReactions {
                inlineReactionStrip(topPadding: 0)
                    .padding(6)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    )
                    .padding(6)
            }
        }
        .frame(maxWidth: 240, alignment: item.isOutgoing ? .trailing : .leading)
        .clipShape(
            RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private func tradeShareBubble(tradeID: TradeID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SharedTradeMessageCard(
                trade: sharedTrade,
                tradeID: tradeID,
                isOutgoing: item.isOutgoing,
                includesBackground: false
            )
            inlineReactionStrip(topPadding: 6)
        }
        .padding(.horizontal, ExperienceSpacing.sm + 2)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, reactionBottomPadding)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .accessibilityIdentifier("conversation.bubble.trade")
    }

    private var reactionsOnlyBubble: some View {
        inlineReactionStrip(topPadding: 0)
            .padding(.horizontal, ExperienceSpacing.sm + 2)
            .padding(.vertical, ExperienceSpacing.xs)
            .frame(maxWidth: bubbleMaxWidth, alignment: item.isOutgoing ? .trailing : .leading)
            .background(
                item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
            )
    }

    @ViewBuilder
    private func inlineReactionStrip(topPadding: CGFloat) -> some View {
        if let reactionConfiguration, reactionConfiguration.showsStrip {
            MessageReactionStrip(
                summaries: reactionConfiguration.summaries,
                supportedEmojis: reactionConfiguration.supportedEmojis,
                isOutgoing: item.isOutgoing,
                isEnabled: reactionConfiguration.isEnabled,
                onToggle: reactionConfiguration.onToggle
            )
            .padding(.top, topPadding)
        }
    }

    private var reactionBottomPadding: CGFloat {
        showsInlineReactions ? ExperienceSpacing.xs + 2 : ExperienceSpacing.sm
    }

    private var bubbleMaxWidth: CGFloat { 260 }
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
                username: profile?.username ?? "?"
            ),
            image: image,
            size: size
        )
        .task(id: profile?.avatar?.id) {
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
