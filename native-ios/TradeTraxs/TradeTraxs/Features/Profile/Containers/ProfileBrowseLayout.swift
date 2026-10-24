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
            .task(id: reference?.id) {
                await load()
            }
    }

    private func load() async {
        guard let reference else {
            displayImage = nil
            return
        }
        let pixelBudget = max(256, Int(180 * displayScale))
        do {
            let data = try await imagePipeline.data(
                for: ImageRequest(
                    reference: reference,
                    purpose: purpose,
                    maxPixelSize: pixelBudget,
                    allowsProgressiveLoading: true,
                    deliveryQuality: .profileGrid
                )
            )
            let scale = displayScale
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data, scale: scale)
            }.value
            displayImage = decoded.map { MediaImageOrientation.normalized($0) }
        } catch {
            displayImage = nil
        }
    }
}

struct ProfileTradeGridTile: View {
    let summary: TradeSummary
    let imagePipeline: any ImagePipeline
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
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
        }
        .buttonStyle(.experiencePlain)
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

struct ProfileClipGridTile: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let title: String
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
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
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("profile.clips.grid.\(reel.id.rawValue)")
    }
}

struct ProfilePostGridTile: View {
    let post: Post
    let imagePipeline: any ImagePipeline
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private var media: MediaReference? {
        ProfileCardMediaPresence.postMedia(in: post)
    }

    var body: some View {
        Button(action: onOpen) {
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
        }
        .buttonStyle(.experiencePlain)
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
    var isPinned: Bool = false
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var media: MediaReference? {
        guard let image = achievement.image else { return nil }
        let trimmed = image.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : image
    }

    var body: some View {
        Button(action: onOpen) {
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
        }
        .buttonStyle(.experiencePlain)
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
