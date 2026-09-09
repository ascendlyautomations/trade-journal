import SwiftUI
import UIKit

/// Compact discoverable Trade Room row — tap body to preview, Join/Request on the right.
struct TradeRoomDiscoveryRow: View {
    let room: ExploreRoomSuggestion
    let joinState: TradeRoomDiscoveryJoinState
    var isYourRoomsContext: Bool = false
    var isOwner: Bool = false
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void
    let onJoin: () -> Void

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

    private let avatarSize: CGFloat = 52

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(room.name)
                                .experienceStyle(.headline, color: colors.primaryText)
                                .lineLimit(1)

                            if room.isOfficial {
                                TradeRoomOfficialBadge(style: .checkmark)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            joinButton
        }
        .padding(ExperienceSpacing.sm)
        .background(
            colors.surfacePrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
        .task(id: room.imageReference?.id) {
            await loadLogo()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tradeRooms.discovery.row.\(room.id.rawValue)")
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
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .frame(minWidth: 72)
        case .idle:
            Button(action: onJoin) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, ExperienceSpacing.sm)
                    .padding(.vertical, 8)
                    .background(colors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!interactive)
            .accessibilityIdentifier("tradeRooms.discovery.join.\(room.id.rawValue)")
        }
    }

    private var avatar: some View {
        Group {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    colors.fillSecondary
                    ExperienceIcon(icon: .rooms, size: .md, color: colors.accent)
                }
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
    }

    private func loadLogo() async {
        guard let reference = room.imageReference else {
            logoImage = nil
            return
        }
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: .profileAvatar,
                    maxPixelSize: 160
                )
            )
            if let ui = UIImage(data: data) {
                logoImage = Image(uiImage: ui)
            }
        } catch {
            logoImage = nil
        }
    }
}
