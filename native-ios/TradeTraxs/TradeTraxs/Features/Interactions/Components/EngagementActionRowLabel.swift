import SwiftUI

enum EngagementBarVisualStyle: Equatable {
    case standard
    case feedCard

    var iconPointSize: CGFloat {
        switch self {
        case .standard: return 18
        case .feedCard: return 20
        }
    }

    var iconWeight: Font.Weight {
        switch self {
        case .standard: return .regular
        case .feedCard: return .medium
        }
    }
}

private struct EngagementBarVisualStyleKey: EnvironmentKey {
    static let defaultValue: EngagementBarVisualStyle = .standard
}

extension EnvironmentValues {
    var engagementBarVisualStyle: EngagementBarVisualStyle {
        get { self[EngagementBarVisualStyleKey.self] }
        set { self[EngagementBarVisualStyleKey.self] = newValue }
    }
}

enum EngagementActionRowMetrics {
    static let iconPointSize: CGFloat = 18
    static let actionContainerSide: CGFloat = 32
    static let iconCountSpacing: CGFloat = 4
    static let rowHeight: CGFloat = 32
}

/// SF Symbol identity for the shared engagement action row.
enum EngagementActionIconKind {
    case like(liked: Bool)
    case comment
    case share
    case vault(vaulted: Bool)

    var systemImage: String {
        switch self {
        case .like(let liked): return liked ? "heart.fill" : "heart"
        case .comment: return "bubble.right"
        case .share: return "square.and.arrow.up"
        case .vault(let vaulted): return vaulted ? "hexagon.fill" : "hexagon"
        }
    }

    /// Y nudge vs comment bubble body top (reference = 0). Ignores tails, arrows, and bottom points.
    var referenceEdgeYOffset: CGFloat {
        switch self {
        case .comment:
            return 0
        case .like:
            return -2
        case .share:
            return -3
        case .vault:
            return -1.5
        }
    }
}

/// Shared SF Symbol in a fixed 32×32 action container.
struct EngagementActionIcon: View {
    let kind: EngagementActionIconKind
    var color: Color

    @Environment(\.engagementBarVisualStyle) private var visualStyle

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: visualStyle.iconPointSize, weight: visualStyle.iconWeight))
            .foregroundStyle(color)
            .offset(y: kind.referenceEdgeYOffset)
            .frame(
                width: EngagementActionRowMetrics.actionContainerSide,
                height: EngagementActionRowMetrics.actionContainerSide,
                alignment: .center
            )
    }
}

/// Fixed-height action slot shared by every action container in ``EngagementBar``.
struct EngagementActionRowContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(height: EngagementActionRowMetrics.rowHeight, alignment: .center)
    }
}

/// Shared icon + optional count layout for engagement actions.
struct EngagementActionRowLabel: View {
    let kind: EngagementActionIconKind
    var count: Int = 0
    var showsCount: Bool = true
    var iconColor: Color
    var iconScale: CGFloat = 1
    var symbolBounce: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: EngagementActionRowMetrics.iconCountSpacing) {
            EngagementActionIcon(kind: kind, color: iconColor)

            if showsCount {
                Text(LikeButton.formatCount(count))
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: EngagementActionRowMetrics.rowHeight, alignment: .center)
    }
}

extension View {
    func engagementActionRowContainer() -> some View {
        EngagementActionRowContainer { self }
    }
}
