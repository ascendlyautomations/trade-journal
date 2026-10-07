import SwiftUI

/// Compact Trade Room card for the Explore horizontal rail — avatar-first like Messages.
struct ExploreRoomCard: View {
    let room: ExploreRoomSuggestion
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesCompactLayout: Bool {
        dynamicTypeSize < .accessibility1
    }

    private let cardWidth: CGFloat = 148
    private let cardHeight: CGFloat = ExploreTraderCard.railHeight
    private let avatarSize: CGFloat = 52
    private let nameRowHeight: CGFloat = 18
    private let detailRowHeight: CGFloat = 14
    private let textRowSpacing: CGFloat = 2

    private var descriptionPreview: String? {
        guard let raw = room.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return raw
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                TradeRoomCircularAvatar(
                    imageReference: room.imageReference,
                    imagePipeline: imagePipeline,
                    diameter: avatarSize,
                    placeholderIconColor: colors.secondaryText
                )

                VStack(alignment: .leading, spacing: textRowSpacing) {
                    HStack(spacing: 4) {
                        Text(room.name)
                            .font(ExperienceTypography.subheadline.weight(.semibold))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)
                        if room.isOfficial {
                            TradeRoomOfficialBadge(style: .checkmark)
                        }
                    }
                    .frame(height: usesCompactLayout ? nameRowHeight : nil, alignment: .center)

                    if let descriptionPreview {
                        Text(descriptionPreview)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(usesCompactLayout ? 1 : 2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: !usesCompactLayout)
                            .frame(height: usesCompactLayout ? detailRowHeight : nil, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let memberCount = room.memberCount {
                        Text("\(ProfileDisplay.compactCount(memberCount)) members")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(usesCompactLayout ? 1 : 2)
                            .truncationMode(.tail)
                            .frame(height: usesCompactLayout ? detailRowHeight : nil, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let owner = room.ownerDisplayLabel {
                        Text(owner)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(usesCompactLayout ? 1 : 2)
                            .truncationMode(.tail)
                            .frame(height: usesCompactLayout ? detailRowHeight : nil, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(ExperienceSpacing.sm)
        .frame(width: cardWidth, height: usesCompactLayout ? cardHeight : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.surfacePrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "person.3")
            }
        } preview: {
            ExploreRoomCard(room: room, imagePipeline: imagePipeline, onOpen: {})
        }
        .accessibilityIdentifier("explore.room.\(room.id.rawValue)")
    }
}
