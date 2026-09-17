import SwiftUI
import UIKit

enum MessageBubbleActionMenuSupport {
    static func estimatedMenuSize(
        emojiCount: Int,
        actionCount: Int
    ) -> CGSize {
        let emojiRowHeight: CGFloat = emojiCount > 0 ? 34 : 0
        let actionRowHeight: CGFloat = 36
        let divider: CGFloat = emojiCount > 0 && actionCount > 0 ? 1 : 0
        let width = max(118, CGFloat(max(emojiCount, 1)) * 28 + 8)
        let height = emojiRowHeight + divider + CGFloat(actionCount) * actionRowHeight + 6
        return CGSize(width: width, height: max(height, emojiRowHeight + 6))
    }

    @MainActor
    static func menu(
        item: ConversationBubbleItem,
        reactionConfiguration: MessageReactionConfiguration?,
        canDelete: Bool,
        deleteMenuTitle: String,
        onRetry: (() -> Void)?,
        onDelete: (() -> Void)?,
        onReport: (() -> Void)?,
        onSelectEmoji: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) -> MessageBubbleActionMenu {
        let reactionsEnabled = item.sendState == .sent && reactionConfiguration?.isEnabled == true
        let emojis = reactionsEnabled ? (reactionConfiguration?.supportedEmojis ?? []) : []
        let selected = reactionConfiguration?.summaries.first(where: \.reactedByViewer)?.emoji

        let copyAction: (() -> Void)? = {
            guard let text = item.text, !text.isEmpty, item.message.kind != .tradeShare else { return nil }
            return {
                UIPasteboard.general.string = text
                ExperienceHaptics.play(.success)
            }
        }()

        let retryAction: (() -> Void)? = item.sendState == .failed ? onRetry : nil
        let deleteAction: (() -> Void)? = canDelete ? onDelete : nil
        let reportAction: (() -> Void)? = !item.isOutgoing ? onReport : nil

        return MessageBubbleActionMenu(
            supportedEmojis: emojis,
            selectedEmoji: selected,
            onSelectEmoji: onSelectEmoji,
            onCopy: copyAction,
            onRetry: retryAction,
            onDelete: deleteAction,
            deleteTitle: deleteMenuTitle,
            onReport: reportAction,
            onDismiss: onDismiss
        )
    }

    static func actionCount(
        item: ConversationBubbleItem,
        reactionConfiguration: MessageReactionConfiguration?,
        canDelete: Bool,
        onRetry: (() -> Void)?,
        onReport: (() -> Void)?
    ) -> Int {
        var count = 0
        if item.text.flatMap({ !$0.isEmpty && item.message.kind != .tradeShare ? $0 : nil }) != nil {
            count += 1
        }
        if item.sendState == .failed, onRetry != nil { count += 1 }
        if canDelete { count += 1 }
        if !item.isOutgoing, onReport != nil { count += 1 }
        _ = reactionConfiguration
        return count
    }

    static func emojiCount(
        item: ConversationBubbleItem,
        reactionConfiguration: MessageReactionConfiguration?
    ) -> Int {
        guard item.sendState == .sent, reactionConfiguration?.isEnabled == true else { return 0 }
        return reactionConfiguration?.supportedEmojis.count ?? 0
    }
}
