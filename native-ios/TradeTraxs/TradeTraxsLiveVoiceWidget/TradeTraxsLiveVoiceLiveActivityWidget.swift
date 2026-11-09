import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveVoiceActivityColors {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.11)
    /// App brand blue (matches experience light accent).
    static let brandBlue = Color(red: 10 / 255, green: 110 / 255, blue: 138 / 255)
    static let connectedGreen = Color(red: 0.20, green: 0.78, blue: 0.55)
    static let leave = Color(red: 0.95, green: 0.32, blue: 0.32)
    static let secondary = Color.white.opacity(0.72)
}

struct TradeTraxsLiveVoiceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TradeTraxsLiveVoiceActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(LiveVoiceActivityColors.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    brandMark(size: 26)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        brandStatusRow(
                            connectionLabel: context.state.connectionLabel,
                            participantCount: context.state.participantCount,
                            showParticipantCount: false,
                            brandFont: .caption.weight(.semibold),
                            statusFont: .caption2.weight(.medium)
                        )
                        Text(context.attributes.tradeRoomName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    participantCountView(context.state.participantCount, font: .caption.weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    liveActivityControls(state: context.state, compact: true)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                brandMark(size: 18)
            } compactTrailing: {
                connectionDot(isConnected: context.state.connectionLabel == "Connected")
            } minimal: {
                brandMark(size: 14)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<TradeTraxsLiveVoiceActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                brandStatusRow(
                    connectionLabel: context.state.connectionLabel,
                    participantCount: context.state.participantCount,
                    showParticipantCount: true,
                    brandFont: .subheadline.weight(.semibold),
                    statusFont: .footnote.weight(.medium)
                )
                Text(context.attributes.tradeRoomName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            liveActivityControls(state: context.state, compact: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func brandStatusRow(
        connectionLabel: String,
        participantCount: Int,
        showParticipantCount: Bool,
        brandFont: Font,
        statusFont: Font
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("TradeTraxs")
                .font(brandFont)
                .foregroundStyle(LiveVoiceActivityColors.brandBlue)
            HStack(spacing: 6) {
                connectionDot(isConnected: connectionLabel == "Connected")
                Text(connectionLabel)
                    .font(statusFont)
                    .foregroundStyle(LiveVoiceActivityColors.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 10)
            if showParticipantCount {
                participantCountView(participantCount, font: statusFont)
            }
        }
    }

    @ViewBuilder
    private func participantCountView(_ count: Int, font: Font) -> some View {
        Label("\(count)", systemImage: "person.2.fill")
            .font(font)
            .foregroundStyle(LiveVoiceActivityColors.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func brandMark(size: CGFloat) -> some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("TradeTraxs")
    }

    @ViewBuilder
    private func connectionDot(isConnected: Bool) -> some View {
        Circle()
            .fill(isConnected ? LiveVoiceActivityColors.connectedGreen : Color.orange)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func liveActivityControls(
        state: TradeTraxsLiveVoiceActivityAttributes.ContentState,
        compact: Bool
    ) -> some View {
        let spacing: CGFloat = compact ? 8 : 10
        let verticalPad: CGFloat = compact ? 9 : 11
        let iconSize: CGFloat = compact ? 14 : 16
        let minHeight: CGFloat = compact ? 54 : 58
        HStack(spacing: spacing) {
            controlLink(
                url: "tradetraxs://live-voice/mute",
                title: state.isMicrophoneEnabled ? "Mute" : "Unmute",
                systemImage: state.isMicrophoneEnabled ? "mic.slash.fill" : "mic.fill",
                tint: .white,
                iconSize: iconSize,
                verticalPad: verticalPad,
                minHeight: minHeight
            )
            controlLink(
                url: "tradetraxs://live-voice/hand",
                title: state.isHandRaised ? "Lower" : "Hand",
                systemImage: "hand.raised.fill",
                tint: state.isHandRaised ? LiveVoiceActivityColors.connectedGreen : .white,
                iconSize: iconSize,
                verticalPad: verticalPad,
                minHeight: minHeight
            )
            controlLink(
                url: "tradetraxs://live-voice/leave",
                title: "Leave",
                systemImage: "phone.down.fill",
                tint: LiveVoiceActivityColors.leave,
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
        tint: Color,
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
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.vertical, verticalPad)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
