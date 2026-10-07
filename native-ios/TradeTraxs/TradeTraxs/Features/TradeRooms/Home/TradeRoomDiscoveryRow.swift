import SwiftUI
import UIKit

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
    var isMuted: Bool = false
    var onToggleMute: (() -> Void)? = nil
    var onLeave: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @State private var logoImage: Image?

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

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Group {
                                if presentation == .plainList {
                                    Text(room.name)
                                        .experienceStyle(.subheadline, color: colors.primaryText)
                                        .fontWeight(.semibold)
                                } else {
                                    Text(room.name)
                                        .experienceStyle(.headline, color: colors.primaryText)
                                }
                            }
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
                                .experienceStyle(
                                    .caption2,
                                    color: presentation == .plainList ? colors.tertiaryText : colors.accent
                                )
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
        .modifier(ElevatedCardChrome(presentation: presentation, colors: colors))
        .contextMenu {
            membershipContextMenu
        }
        .task(id: room.imageReference?.id) {
            await loadLogo()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tradeRooms.discovery.row.\(room.id.rawValue)")
    }

    @ViewBuilder
    private var membershipContextMenu: some View {
        if onLeave != nil || onToggleMute != nil {
            Button(action: onOpen) {
                Label("Open", systemImage: "person.3")
            }
            if let onToggleMute {
                Button(action: onToggleMute) {
                    Label(
                        isMuted ? "Unmute" : "Mute",
                        systemImage: isMuted ? "bell.fill" : "bell.slash"
                    )
                }
            }
            if let onLeave {
                Divider()
                Button(role: .destructive, action: onLeave) {
                    Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
                }
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
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .frame(minWidth: 72)
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
                    ExperienceIcon(
                        icon: .rooms,
                        size: presentation == .plainList ? .sm : .md,
                        color: presentation == .plainList ? colors.secondaryText : colors.accent
                    )
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
