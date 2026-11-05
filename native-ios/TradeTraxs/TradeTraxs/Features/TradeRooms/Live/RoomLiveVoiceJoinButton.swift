import SwiftUI

struct RoomLiveVoiceJoinButton: View {
    let channel: RoomChannel
    let roomTitle: String
    @Bindable var coordinator: RoomLiveVoiceCoordinator

    @Environment(\.themeColors) private var colors

    var body: some View {
        if !channel.liveKind.supportsLiveVoice {
            EmptyView()
        } else if coordinator.session?.sectionID == channel.id,
                  coordinator.isSessionActive
        {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .foregroundStyle(colors.accent)
                Text("In voice")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
        } else {
            Button {
                Task {
                    await coordinator.join(
                        roomID: channel.roomID,
                        sectionID: channel.id,
                        roomTitle: roomTitle,
                        channelTitle: channel.displayTitle
                    )
                }
            } label: {
                Label(coordinator.isJoining ? "Joining…" : "Join voice", systemImage: "headphones")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryBackground)
                    .padding(.horizontal, ExperienceSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(colors.accent))
            }
            .buttonStyle(.experiencePlain)
            .disabled(coordinator.isJoining)
            .accessibilityIdentifier("tradeRooms.liveVoice.join")
        }
    }
}
