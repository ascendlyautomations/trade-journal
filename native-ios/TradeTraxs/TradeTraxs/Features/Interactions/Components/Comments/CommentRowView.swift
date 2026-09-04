import SwiftUI
import UIKit

struct CommentRowView: View {
    let comment: InteractionComment
    let isOwn: Bool
    let imagePipeline: any ImagePipeline
    let likeSnapshot: CommentLikeSnapshot
    let canLike: Bool
    let isLikeBusy: Bool
    let onToggleLike: () -> Void
    let canPin: Bool
    let isPinBusy: Bool
    let onTogglePin: ((Bool) -> Void)?
    var onDelete: (() -> Void)?

    var onReport: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    private var isPinnedTopLevel: Bool {
        CommentPinSemantics.isCommentPinned(comment)
    }

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            CommentAuthorAvatarView(
                comment: comment,
                imagePipeline: imagePipeline,
                size: 32
            )

            VStack(alignment: .leading, spacing: 4) {
                if isPinnedTopLevel {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Pinned")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    .accessibilityIdentifier("interaction.comment.pinned")
                }
                HStack(spacing: ExperienceSpacing.xs) {
                    Text(comment.authorUsername.map { "@\($0)" } ?? "Trader")
                        .experienceStyle(.footnote, color: colors.primaryText)
                    Text(TradeDisplay.dateText(comment.createdAt))
                        .experienceStyle(.caption, color: colors.tertiaryText)
                    Spacer(minLength: 0)
                }
                Text(comment.body)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: ExperienceSpacing.sm) {
                    CommentLikeButton(
                        snapshot: likeSnapshot,
                        isEnabled: canLike,
                        isBusy: isLikeBusy,
                        onToggle: onToggleLike
                    )
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = comment.body
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if canPin, let onTogglePin {
                if isPinnedTopLevel {
                    Button {
                        onTogglePin(false)
                    } label: {
                        Label("Unpin", systemImage: "pin.slash")
                    }
                    .disabled(isPinBusy)
                } else {
                    Button {
                        onTogglePin(true)
                    } label: {
                        Label("Pin", systemImage: "pin")
                    }
                    .disabled(isPinBusy)
                }
            }
            if isOwn, let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            if !isOwn, let onReport {
                Divider()
                Button(action: onReport) {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("interaction.comment.row.\(comment.id.rawValue)")
    }

    private var accessibilitySummary: String {
        let author = comment.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named: String = {
            if let author, !author.isEmpty { return author }
            if let username = comment.authorUsername, !username.isEmpty { return "@\(username)" }
            return "Trader"
        }()
        return "\(named). \(comment.body)"
    }
}

/// Loads the comment author's avatar via the shared ``ImagePipeline`` cache.
/// Uses the avatar URL already joined on the comment — never fetches profiles per row.
private struct CommentAuthorAvatarView: View {
    let comment: InteractionComment
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 32

    @State private var image: Image?

    var body: some View {
        ExperienceAvatar(
            initials: Self.initials(for: comment),
            image: image,
            size: size
        )
        .task(id: comment.authorAvatarURL ?? comment.authorProfileID.rawValue) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let reference = comment.authorAvatarReference else {
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

    private static func initials(for comment: InteractionComment) -> String {
        ProfileDisplay.initials(
            displayName: comment.authorDisplayName ?? "",
            username: comment.authorUsername ?? "tr"
        )
    }
}
