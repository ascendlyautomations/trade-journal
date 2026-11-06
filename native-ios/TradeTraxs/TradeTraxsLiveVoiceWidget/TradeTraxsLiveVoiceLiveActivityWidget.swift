import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveVoiceActivityColors {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.55)
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
                    brandMark(size: 22)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.tradeRoomName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(context.state.participantCount) · \(context.state.connectionLabel)")
                            .font(.caption2)
                            .foregroundStyle(LiveVoiceActivityColors.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    connectionDot(isConnected: context.state.connectionLabel == "Connected")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    liveActivityControls(state: context.state, compact: true)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                brandMark(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TradeTraxs")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiveVoiceActivityColors.accent)
                    HStack(spacing: 4) {
                        connectionDot(isConnected: context.state.connectionLabel == "Connected")
                        Text(context.state.connectionLabel)
                            .font(.caption2)
                            .foregroundStyle(LiveVoiceActivityColors.secondary)
                    }
                }
                Spacer(minLength: 0)
                Label("\(context.state.participantCount)", systemImage: "person.2.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LiveVoiceActivityColors.secondary)
            }

            Text(context.attributes.tradeRoomName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            liveActivityControls(state: context.state, compact: false)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func brandMark(size: CGFloat) -> some View {
        Image("TradeTraxsLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("TradeTraxs")
    }

    @ViewBuilder
    private func connectionDot(isConnected: Bool) -> some View {
        Circle()
            .fill(isConnected ? LiveVoiceActivityColors.accent : Color.orange)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func liveActivityControls(
        state: TradeTraxsLiveVoiceActivityAttributes.ContentState,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            controlLink(
                url: "tradetraxs://live-voice/mute",
                title: state.isMicrophoneEnabled ? "Mute" : "Unmute",
                systemImage: state.isMicrophoneEnabled ? "mic.slash.fill" : "mic.fill",
                tint: .white
            )
            controlLink(
                url: "tradetraxs://live-voice/hand",
                title: state.isHandRaised ? "Lower" : "Hand",
                systemImage: "hand.raised.fill",
                tint: state.isHandRaised ? LiveVoiceActivityColors.accent : .white
            )
            controlLink(
                url: "tradetraxs://live-voice/leave",
                title: "Leave",
                systemImage: "phone.down.fill",
                tint: LiveVoiceActivityColors.leave
            )
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
    }

    @ViewBuilder
    private func controlLink(
        url: String,
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compactControlPadding)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var compactControlPadding: CGFloat { 8 }
}
