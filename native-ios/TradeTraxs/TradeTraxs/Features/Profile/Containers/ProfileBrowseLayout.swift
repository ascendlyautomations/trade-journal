import SwiftUI
import UIKit

/// Profile tab browse mode. Persisted per tab across navigation and relaunch.
enum ProfileBrowseLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }
}

enum ProfileBrowseLayoutTab: String {
    case trades
    case clips
    case posts
    case achievements
}

enum ProfileBrowseLayoutStore {
    static func layout(for tab: ProfileBrowseLayoutTab) -> ProfileBrowseLayout {
        let raw = UserDefaults.standard.string(forKey: key(tab)) ?? ""
        return ProfileBrowseLayout(rawValue: raw) ?? .list
    }

    static func save(_ layout: ProfileBrowseLayout, for tab: ProfileBrowseLayoutTab) {
        UserDefaults.standard.set(layout.rawValue, forKey: key(tab))
    }

    private static func key(_ tab: ProfileBrowseLayoutTab) -> String {
        "profile.browseLayout.\(tab.rawValue)"
    }
}

/// Shared Grid / List control for Profile Trades, Clips, Posts, and Achievements.
struct ProfileBrowseLayoutToggle: View {
    @Binding var layout: ProfileBrowseLayout
    var compact: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProfileBrowseLayout.allCases) { mode in
                Button {
                    layout = mode
                } label: {
                    Image(systemName: mode == .grid ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .foregroundStyle(layout == mode ? colors.primaryText : colors.tertiaryText)
                        .frame(width: compact ? 26 : 32, height: compact ? 24 : 28)
                        .background(layout == mode ? colors.surfacePrimary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(layout == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(colors.fillSecondary)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.browseLayout.toggle")
    }
}

struct ProfileBrowseGridImage: View {
    let reference: MediaReference?
    let purpose: ImagePurpose
    let imagePipeline: any ImagePipeline

    @Environment(\.displayScale) private var displayScale
    @Environment(\.themeColors) private var colors
    @State private var displayImage: UIImage?

    init(reference: MediaReference?, purpose: ImagePurpose, imagePipeline: any ImagePipeline) {
        self.reference = reference
        self.purpose = purpose
        self.imagePipeline = imagePipeline
        if let reference {
            _displayImage = State(
                initialValue: ProfileBrowseMediaDisplayCache.uiImage(
                    reference: reference,
                    purpose: purpose
                )
            )
        } else {
            _displayImage = State(initialValue: nil)
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFill()
                } else if reference != nil {
                    colors.fillPrimary
                }
            }
            .clipped()
            .task(id: loadTaskID) {
                await load()
            }
    }

    private var loadTaskID: String {
        guard let reference else { return "" }
        return ProfileBrowseMediaDisplayCache.cacheKey(reference: reference, purpose: purpose)
    }

    private func load() async {
        guard let reference else {
            displayImage = nil
            return
        }
        if displayImage != nil { return }
        let pixelBudget = ProfileBrowseMediaLoader.gridPixelBudget(displayScale: displayScale)
        let loaded = await ProfileBrowseMediaLoader.loadUIImage(
            reference: reference,
            purpose: purpose,
            maxPixelSize: pixelBudget,
            displayScale: displayScale,
            imagePipeline: imagePipeline,
            existing: displayImage
        )
        displayImage = loaded
    }
}

struct ProfileTradeGridTile: View {
    let summary: TradeSummary
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var target: InteractionTarget { .trade(summary.id) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let media = ProfileCardMediaPresence.tradeMedia(in: summary) {
                ProfileBrowseGridImage(
                    reference: media,
                    purpose: .tradeScreenshot,
                    imagePipeline: imagePipeline
                )
            } else {
                tradeFallback
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.symbol.ticker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(TradeDisplay.pnlText(summary.realizedPnL))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(pnlColor)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.72), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .overlay(alignment: .topTrailing) {
            if isPinned {
                ProfileGridPinBadge()
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .experienceDoubleTapLike(
            target: target,
            store: engagementStore,
            anchorsHeartToTapLocation: true,
            onSingleTap: onOpen
        )
        .accessibilityLabel(tradeGridAccessibilityLabel)
        .accessibilityIdentifier("profile.trades.grid.\(summary.id.rawValue)")
    }

    private var tradeGridAccessibilityLabel: String {
        let base = "\(summary.symbol.ticker), \(TradeDisplay.pnlText(summary.realizedPnL))"
        return isPinned ? "\(base), pinned to profile" : base
    }

    private var tradeFallback: some View {
        colors.fillPrimary
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ExperienceIcon(icon: .chart, size: .lg, color: colors.tertiaryText)
            }
    }

    private var pnlColor: Color {
        theme.metricColor(
            for: NSDecimalNumber(decimal: summary.realizedPnL?.amount ?? 0).doubleValue
        )
    }
}

/// Grid thumbnail overflow — matches list cards; light icon on photo tiles.
private struct ProfileBrowseGridOwnerOverflow: View {
    let isOwner: Bool
    var deleteTitle: String = "Delete"
    var onDelete: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var onUnpin: (() -> Void)? = nil
    var isPinnedToProfile = false
    var accessibilityIdentifier: String

    var body: some View {
        ContentOverflowMenu(
            isOwner: isOwner,
            deleteTitle: deleteTitle,
            onDelete: onDelete,
            onPin: onPin,
            onUnpin: onUnpin,
            isPinnedToProfile: isPinnedToProfile,
            foregroundColor: .white,
            accessibilityIdentifier: accessibilityIdentifier
        )
        .padding(ExperienceSpacing.xxs)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

struct ProfileClipGridTile: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let title: String
    var isOwner: Bool = false
    var isPinned: Bool = false
    var profilePin: ProfilePinCallbacks? = nil
    var isDeleteInProgress: Bool = false
    var onDelete: (() -> Void)? = nil
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private var target: InteractionTarget { .reel(reel.id) }

    private var isPinnedToProfile: Bool {
        isPinned || (profilePin?.isPinned(.reel, reel.id.rawValue) ?? false)
    }

    var body: some View {
        ZStack {
            if let thumbnail = reel.thumbnail {
                ProfileBrowseGridImage(
                    reference: thumbnail,
                    purpose: .reelThumbnail,
                    imagePipeline: imagePipeline
                )
            } else {
                colors.fillPrimary
                    .aspectRatio(1, contentMode: .fit)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
        .overlay(alignment: .topLeading) {
            if isOwner {
                ProfileBrowseGridOwnerOverflow(
                    isOwner: true,
                    deleteTitle: "Delete Clip",
                    onDelete: isDeleteInProgress ? nil : onDelete,
                    onPin: profilePin.map { pin in
                        {
                            pin.requestPin(
                                .reel,
                                reel.id.rawValue,
                                ProfilePinnedPreviewBuilder.from(reel: reel)
                            )
                        }
                    },
                    onUnpin: profilePin.map { pin in
                        {
                            pin.requestPin(
                                .reel,
                                reel.id.rawValue,
                                ProfilePinnedPreviewBuilder.from(reel: reel)
                            )
                        }
                    },
                    isPinnedToProfile: isPinnedToProfile,
                    accessibilityIdentifier: "profile.clip.overflow.\(reel.id.rawValue)"
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPinnedToProfile {
                ProfileGridPinBadge()
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .experienceDoubleTapLike(
            target: target,
            store: engagementStore,
            anchorsHeartToTapLocation: true,
            onSingleTap: onOpen
        )
        .accessibilityLabel(gridAccessibilityLabel)
        .accessibilityIdentifier("profile.clips.grid.\(reel.id.rawValue)")
    }

    private var gridAccessibilityLabel: String {
        isPinnedToProfile ? "\(title), pinned to profile" : title
    }
}

struct ProfilePostGridTile: View {
    let post: Post
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private var media: MediaReference? {
        ProfileCardMediaPresence.postMedia(in: post)
    }

    private var target: InteractionTarget { .profilePost(post.id) }

    var body: some View {
        Group {
            if let media {
                ProfileBrowseGridImage(
                    reference: media,
                    purpose: .postImage,
                    imagePipeline: imagePipeline
                )
            } else if let share = post.roomShare {
                ProfileRoomShareGridFace(
                    share: share,
                    imagePipeline: imagePipeline,
                    reservesPinSpace: isPinned
                )
            } else {
                colors.fillPrimary
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text(profilePostGridLabel(post))
                            .font(.caption)
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .padding(10)
                            .padding(.trailing, isPinned ? 28 : 0)
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPinned {
                ProfileGridPinBadge()
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .experienceDoubleTapLike(
            target: target,
            store: engagementStore,
            anchorsHeartToTapLocation: true,
            onSingleTap: onOpen
        )
        .accessibilityLabel(postGridAccessibilityLabel)
        .accessibilityIdentifier("profile.posts.grid.\(post.id.rawValue)")
    }

    private var postGridAccessibilityLabel: String {
        let label: String
        if media == nil, post.roomShare != nil {
            let name = post.roomShare?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            label = name.isEmpty ? "Join my trade room" : "Join my trade room, \(name)"
        } else {
            label = profilePostGridLabel(post)
        }
        let base = label.isEmpty ? "Post" : label
        return isPinned ? "\(base), pinned to profile" : base
    }
}

/// Grid face for a room-share post that has no photo of its own.
private struct ProfileRoomShareGridFace: View {
    let share: RoomShareAttachment
    let imagePipeline: any ImagePipeline
    var reservesPinSpace: Bool = false

    @Environment(\.themeColors) private var colors

    private var roomLogo: MediaReference? {
        let raw = share.logoURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return MediaReference(id: raw, kind: .image, altText: share.name)
    }

    private var roomName: String {
        share.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let roomLogo {
                ProfileBrowseGridImage(
                    reference: roomLogo,
                    purpose: .profileAvatar,
                    imagePipeline: imagePipeline
                )
            } else {
                colors.fillPrimary
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExperienceIcon(icon: .rooms, size: .lg, color: colors.accent)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Join my trade room")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !roomName.isEmpty {
                    Text(roomName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .padding(.trailing, reservesPinSpace ? 22 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.78), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .accessibilityIdentifier("profile.posts.grid.roomShare.\(share.roomID.rawValue)")
    }
}

struct ProfileAchievementGridTile: View {
    let achievement: Achievement
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var media: MediaReference? {
        guard let image = achievement.image else { return nil }
        let trimmed = image.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : image
    }

    private var target: InteractionTarget { .achievement(achievement.id) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let media {
                ProfileBrowseGridImage(
                    reference: media,
                    purpose: .postImage,
                    imagePipeline: imagePipeline
                )
            } else {
                colors.fillPrimary
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExperienceIcon(icon: .trophy, size: .lg, color: colors.tertiaryText)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let valueText = overlayValueText {
                    Text(valueText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .padding(.trailing, isPinned ? 22 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.72), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .overlay(alignment: .topTrailing) {
            if isPinned {
                ProfileGridPinBadge()
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .contentShape(Rectangle())
        .experienceDoubleTapLike(
            target: target,
            store: engagementStore,
            anchorsHeartToTapLocation: true,
            onSingleTap: onOpen
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("profile.achievements.grid.\(achievement.id.rawValue)")
    }

    private var overlayValueText: String? {
        if ProfilePayoutTotals.isPayout(achievement.kind) {
            return ProfilePayoutTotals.payoutDisplayText(for: achievement)
        }
        if let value = achievement.value {
            return TradeDisplay.pnlText(value)
        }
        let trimmed = achievement.valueText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var valueColor: Color {
        guard let value = achievement.value else { return .white }
        return theme.metricColor(for: NSDecimalNumber(decimal: value.amount).doubleValue)
    }

    private var accessibilityLabel: String {
        var parts = [achievement.title]
        if let overlayValueText {
            parts.append(overlayValueText)
        }
        if isPinned {
            parts.append("pinned to profile")
        }
        return parts.joined(separator: ", ")
    }
}

private func profilePostGridLabel(_ post: Post) -> String {
    let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
    if !body.isEmpty { return body }
    return post.roomShare?.name ?? ""
}
