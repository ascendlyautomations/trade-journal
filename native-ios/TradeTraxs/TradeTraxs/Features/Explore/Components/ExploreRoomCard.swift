import SwiftUI

/// Compact Trade Room card for the Explore horizontal rail — avatar-first like Messages.
struct ExploreRoomCard: View {
    let room: ExploreRoomSuggestion
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private let avatarSize: CGFloat = 52

    private var descriptionPreview: String? {
        guard let raw = room.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return raw
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                TradeRoomCircularAvatar(
                    imageReference: room.imageReference,
                    imagePipeline: imagePipeline,
                    diameter: avatarSize
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(room.name)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if room.isOfficial {
                            TradeRoomOfficialBadge(style: .checkmark)
                        }
                    }

                    if let descriptionPreview {
                        Text(descriptionPreview)
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let memberCount = room.memberCount {
                        Text("\(ProfileDisplay.compactCount(memberCount)) members")
                            .experienceStyle(.caption, color: colors.secondaryText)
                            .lineLimit(1)
                    }

                    if let owner = room.ownerDisplayLabel {
                        Text(owner)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(ExperienceSpacing.sm)
            .frame(width: 148, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .fill(colors.surfacePrimary)
            )
        }
        .buttonStyle(.plain)
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
