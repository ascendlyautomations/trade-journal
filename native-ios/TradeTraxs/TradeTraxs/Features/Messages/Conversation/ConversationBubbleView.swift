import SwiftUI
import UIKit

struct ConversationBubbleView: View {
    let item: ConversationBubbleItem
    let peerProfile: Profile?
    let imagePipeline: any ImagePipeline
    var sharedTrade: Trade? = nil
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
                SharedTradeMessageCard(
                    trade: sharedTrade,
                    tradeID: tradeID,
                    isOutgoing: item.isOutgoing
                )
            } else if let reference = item.imageReference, item.message.kind != .tradeShare {
                AspectFitMediaView(
                    reference: reference,
                    purpose: .tradeScreenshot,
                    imagePipeline: imagePipeline,
                    accessibilityIdentifier: "conversation.bubble.image",
                    emptyIcon: .photo,
                    allowsFullResolutionViewer: true
                )
                .frame(maxWidth: 240)
                .clipShape(
                    RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
            }

            if item.message.kind != .tradeShare, let text = item.text {
                Text(text)
                    .experienceStyle(
                        .body,
                        color: item.isOutgoing ? colors.onAccent : colors.primaryText
                    )
                    .padding(.horizontal, ExperienceSpacing.sm + 2)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .background(
                        item.isOutgoing ? colors.accent : colors.incomingMessageBubble,
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    )
            }
        }
        .opacity(item.sendState == .sending ? 0.72 : 1)
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
