import SwiftUI

struct RoomLiveVoiceJoinButton: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var coordinator: RoomLiveVoiceCoordinator

    @Environment(\.themeColors) private var colors

    var body: some View {
        if coordinator.session?.roomID == roomID, coordinator.isSessionActive {
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
                    await coordinator.join(roomID: roomID, roomTitle: roomTitle)
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
