import SwiftUI
import UIKit

/// Horizontal post browse card — thumbnail left, truncated caption right (Clips/Trades style).
struct ProfilePostCard: View {
    let post: Post
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let onOpen: () -> Void

    private var target: InteractionTarget { .profilePost(post.id) }
    private let thumbnailSide: CGFloat = 96

    private var caption: String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Post" : trimmed
    }

    private var mediaReference: MediaReference? {
        ProfileCardMediaPresence.postMedia(in: post)
    }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Group {
                    if let mediaReference {
                        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                            TradeImageView(
                                reference: mediaReference,
                                imagePipeline: imagePipeline,
                                purpose: .postImage,
                                contentMode: .fill,
                                side: thumbnailSide
                            )
                            .accessibilityHidden(true)

                            PostCardTextPreview(
                                text: caption,
                                maxHeight: thumbnailSide,
                                isPinned: post.isPinned,
                                dateText: TradeDisplay.dateText(post.createdAt)
                            )
                            .frame(maxWidth: .infinity, maxHeight: thumbnailSide, alignment: .topLeading)
                        }
                    } else {
                        PostCardTextPreview(
                            text: caption,
                            maxHeight: nil,
                            isPinned: post.isPinned,
                            dateText: TradeDisplay.dateText(post.createdAt)
                        )
                    }
                }
                .contentShape(Rectangle())
                .experienceDoubleTapLike(
                    target: target,
                    store: engagementStore,
                    onSingleTap: onOpen
                )
                .accessibilityLabel(accessibilityLabel)

                EngagementBar(
                    target: target,
                    store: engagementStore,
                    onCommentTap: onOpen
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.posts.card.\(post.id.rawValue)")
    }

    private var accessibilityLabel: String {
        var parts = [caption, TradeDisplay.dateText(post.createdAt)]
        if post.isPinned { parts.insert("Pinned", at: 0) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Truncating preview

/// Caption clipped to the thumbnail height; shows link-styled “See more...” only when truncated.
private struct PostCardTextPreview: View {
    let text: String
    let maxHeight: CGFloat?
    let isPinned: Bool
    let dateText: String

    @Environment(\.themeColors) private var colors
    @State private var isTruncated = false

    var body: some View {
        if let maxHeight {
            thumbnailAlignedPreview(maxHeight: maxHeight)
        } else {
            mediaLessPreview
        }
    }

    private var mediaLessPreview: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            previewHeader

            Text(text)
                .experienceStyle(.body, color: colors.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func thumbnailAlignedPreview(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            previewHeader

            Text(text)
                .experienceStyle(.body, color: colors.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(isTruncated ? 3 : nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if isTruncated {
                Text("See more...")
                    .font(.footnote.weight(.regular))
                    .foregroundStyle(Color(uiColor: .link))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
        .clipped()
        .background(alignment: .top) {
            measurementProbe
        }
        .onPreferenceChange(PostPreviewFullHeightKey.self) { fullHeight in
            isTruncated = fullHeight > maxHeight + 0.5
        }
    }

    private var previewHeader: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            if isPinned {
                ExperienceTag(title: "Pinned", tone: .info)
            }
            Text(dateText)
                .experienceStyle(.caption, color: colors.secondaryText)
            Spacer(minLength: 0)
        }
    }

    /// Invisible full-height probe at the same width as the visible text column.
    private var measurementProbe: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(spacing: ExperienceSpacing.xs) {
                if isPinned {
                    ExperienceTag(title: "Pinned", tone: .info)
                }
                Text(dateText)
                    .experienceStyle(.caption, color: .clear)
                Spacer(minLength: 0)
            }
            Text(text)
                .experienceStyle(.body, color: .clear)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hidden()
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PostPreviewFullHeightKey.self,
                    value: geo.size.height
                )
            }
        )
    }
}

private struct PostPreviewFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
