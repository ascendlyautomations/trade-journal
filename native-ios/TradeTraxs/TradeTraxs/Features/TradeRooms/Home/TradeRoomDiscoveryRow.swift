import SwiftUI

/// Compact discoverable Trade Room row — tap body to preview, Join/Request on the right.
struct TradeRoomDiscoveryRow: View {
    enum Presentation {
        /// Raised card — Trade Rooms discovery lists.
        case elevatedCard
        /// Flat row — Explore search, aligned with people results.
        case plainList
    }

    let room: ExploreRoomSuggestion
    let joinState: TradeRoomDiscoveryJoinState
    var isYourRoomsContext: Bool = false
    var isOwner: Bool = false
    var presentation: Presentation = .elevatedCard
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void
    let onJoin: () -> Void
    var isFavorited: Bool = false
    var onToggleFavorite: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    private var avatarSize: CGFloat {
        presentation == .plainList ? 40 : 52
    }

    private var rowSpacing: CGFloat {
        presentation == .plainList ? ExperienceSpacing.md : ExperienceSpacing.sm
    }

    var body: some View {
        HStack(alignment: .center, spacing: rowSpacing) {
            Button(action: onOpen) {
                HStack(alignment: presentation == .plainList ? .center : .top, spacing: rowSpacing) {
                    avatar

                    if presentation == .plainList {
                        plainListDetails
                        Spacer(minLength: ExperienceSpacing.sm)
                    } else {
                        elevatedListDetails
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.experiencePlain)

            joinButton
        }
        .modifier(ElevatedCardChrome(presentation: presentation, colors: colors))
        .contextMenu {
            favoriteContextMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tradeRooms.discovery.row.\(room.id.rawValue)")
    }

    private var plainListDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(room.name)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if room.isOfficial {
                    TradeRoomOfficialBadge(style: .label)
                }
            }

            if let secondary = plainListSecondaryLine {
                Text(secondary)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }

            if let tertiary = plainListTertiaryLine {
                Text(tertiary)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elevatedListDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(room.name)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)

                if room.isOfficial {
                    TradeRoomOfficialBadge(style: .label)
                }
                if isFavorited {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(colors.accent)
                        .accessibilityLabel("Favorited")
                }
            }

            if let description = room.description?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty
            {
                Text(description)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } else if let tagsLine = room.tagsLine {
                Text(tagsLine)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .lineLimit(1)
            }

            HStack(spacing: ExperienceSpacing.xxs) {
                if let memberCount = room.memberCount {
                    Text("\(ProfileDisplay.compactCount(memberCount)) members")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                if let owner = room.ownerDisplayLabel, !room.isOfficial {
                    if room.memberCount != nil {
                        Text("·")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Text(owner)
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .lineLimit(1)
                }
            }

            if let followed = room.followedMemberCount, followed > 0 {
                Text(followed == 1 ? "1 trader you follow" : "\(followed) traders you follow")
                    .experienceStyle(.caption2, color: colors.accent)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plainListSecondaryLine: String? {
        if let description = room.description?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty
        {
            return description
        }
        if let tagsLine = room.tagsLine {
            return tagsLine
        }
        if let memberCount = room.memberCount {
            return "\(ProfileDisplay.compactCount(memberCount)) members"
        }
        return nil
    }

    private var plainListTertiaryLine: String? {
        let hasDescription = room.description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if hasDescription, let memberCount = room.memberCount {
            return "\(ProfileDisplay.compactCount(memberCount)) members"
        }
        if let owner = room.ownerDisplayLabel, !room.isOfficial {
            return owner
        }
        return nil
    }

    @ViewBuilder
    private var favoriteContextMenu: some View {
        if let onToggleFavorite {
            Button(action: onToggleFavorite) {
                Label(
                    isFavorited ? "Unfavorite Room" : "Favorite Room",
                    systemImage: isFavorited ? "star.fill" : "star"
                )
            }
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        let title = TradeRoomJoinPresentation.discoveryStatusTitle(
            isYourRoomsContext: isYourRoomsContext,
            isOwner: isOwner,
            joinPolicy: room.joinPolicy,
            state: joinState
        )
        let interactive = TradeRoomJoinPresentation.isInteractive(joinState)

        switch joinState {
        case .joining, .requesting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 72)
        case .joined, .requested:
            if presentation == .plainList {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(colors.fillSecondary))
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(minWidth: 72)
            }
        case .idle:
            Button(action: onJoin) {
                Text(title)
                    .font(presentation == .plainList ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, presentation == .plainList ? 12 : ExperienceSpacing.sm)
                    .frame(height: presentation == .plainList ? 30 : nil)
                    .padding(.vertical, presentation == .plainList ? 0 : 8)
                    .background(colors.accent, in: Capsule())
            }
            .buttonStyle(.experiencePlain)
            .disabled(!interactive)
            .accessibilityIdentifier("tradeRooms.discovery.join.\(room.id.rawValue)")
        }
    }

    private var avatar: some View {
        TradeRoomCircularAvatar(
            imageReference: room.imageReference,
            imagePipeline: imagePipeline,
            diameter: avatarSize,
            placeholderIconColor: presentation == .plainList ? colors.secondaryText : colors.accent
        )
    }
}

private struct ElevatedCardChrome: ViewModifier {
    let presentation: TradeRoomDiscoveryRow.Presentation
    let colors: SemanticColorPalette

    func body(content: Content) -> some View {
        switch presentation {
        case .elevatedCard:
            content
                .padding(ExperienceSpacing.sm)
                .background(
                    colors.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous))
        case .plainList:
            content
                .contentShape(Rectangle())
        }
    }
}
