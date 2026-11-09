import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveBroadcastActivityColors {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let brandBlue = Color(red: 10 / 255, green: 110 / 255, blue: 138 / 255)
    static let liveRed = Color(red: 0.95, green: 0.28, blue: 0.32)
    static let connectedGreen = Color(red: 0.20, green: 0.78, blue: 0.55)
    static let leave = Color(red: 0.95, green: 0.32, blue: 0.32)
    static let secondary = Color.white.opacity(0.72)
}

struct TradeTraxsLiveBroadcastLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TradeTraxsLiveBroadcastActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(LiveBroadcastActivityColors.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveBadge(compact: false)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        broadcastStatusRow(
                            context: context,
                            brandFont: .caption.weight(.semibold),
                            statusFont: .caption2.weight(.medium),
                            showViewerCount: false
                        )
                        Text(context.attributes.tradeRoomName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    viewerCountView(context.state.viewerCount, font: .caption.weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    broadcastControls(context: context, compact: true)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                liveBadge(compact: true)
            } compactTrailing: {
                connectionDot(isConnected: context.state.connectionLabel == "Listening")
            } minimal: {
                liveBadge(compact: true)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<TradeTraxsLiveBroadcastActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            broadcastStatusRow(
                context: context,
                brandFont: .subheadline.weight(.semibold),
                statusFont: .footnote.weight(.medium),
                showViewerCount: true
            )
            Text(context.attributes.tradeRoomName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            broadcastControls(context: context, compact: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func broadcastStatusRow(
        context: ActivityViewContext<TradeTraxsLiveBroadcastActivityAttributes>,
        brandFont: Font,
        statusFont: Font,
        showViewerCount: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("TradeTraxs")
                .font(brandFont)
                .foregroundStyle(LiveBroadcastActivityColors.brandBlue)
            if context.state.isLive {
                liveBadge(compact: true)
            }
            HStack(spacing: 6) {
                connectionDot(isConnected: context.state.connectionLabel == "Listening")
                Text(context.state.connectionLabel)
                    .font(statusFont)
                    .foregroundStyle(LiveBroadcastActivityColors.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 10)
            if showViewerCount {
                viewerCountView(context.state.viewerCount, font: statusFont)
            }
        }
    }

    @ViewBuilder
    private func liveBadge(compact: Bool) -> some View {
        Text("LIVE")
            .font(compact ? .system(size: 9, weight: .bold) : .caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(LiveBroadcastActivityColors.liveRed)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func viewerCountView(_ count: Int, font: Font) -> some View {
        Label("\(count)", systemImage: "eye.fill")
            .font(font)
            .foregroundStyle(LiveBroadcastActivityColors.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func connectionDot(isConnected: Bool) -> some View {
        Circle()
            .fill(isConnected ? LiveBroadcastActivityColors.connectedGreen : Color.orange)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func broadcastControls(
        context: ActivityViewContext<TradeTraxsLiveBroadcastActivityAttributes>,
        compact: Bool
    ) -> some View {
        let spacing: CGFloat = compact ? 8 : 10
        let verticalPad: CGFloat = compact ? 9 : 11
        let iconSize: CGFloat = compact ? 14 : 16
        let minHeight: CGFloat = compact ? 54 : 58
        let room = context.attributes.roomID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? context.attributes.roomID
        HStack(spacing: spacing) {
            controlLink(
                url: "tradetraxs://live-broadcast/return?room=\(room)",
                title: compact ? "Return" : "Return to Stream",
                systemImage: "play.rectangle.fill",
                foreground: .white,
                background: LiveBroadcastActivityColors.brandBlue.opacity(0.35),
                iconSize: iconSize,
                verticalPad: verticalPad,
                minHeight: minHeight
            )
            controlLink(
                url: "tradetraxs://live-broadcast/leave?room=\(room)",
                title: compact ? "Leave" : "Leave Stream",
                systemImage: "xmark.circle.fill",
                foreground: LiveBroadcastActivityColors.leave,
                background: Color.white.opacity(0.08),
                iconSize: iconSize,
                verticalPad: verticalPad,
                minHeight: minHeight
            )
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
    }

    @ViewBuilder
    private func controlLink(
        url: String,
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        iconSize: CGFloat,
        verticalPad: CGFloat,
        minHeight: CGFloat
    ) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.vertical, verticalPad)
            .padding(.horizontal, 6)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
