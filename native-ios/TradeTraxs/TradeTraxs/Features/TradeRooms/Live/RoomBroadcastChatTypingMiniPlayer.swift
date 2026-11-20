import SwiftUI

/// Viewer-only: program video floating top-trailing while the chat composer is focused.
struct RoomBroadcastChatTypingMiniPlayer: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 136

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForExpandedViewer,
                isFullscreen: false
            )
            .id(coordinator.programVideoTrackRevision)
            RoomBroadcastStreamPlaybackMuteButton(coordinator: coordinator)
                .padding(ExperienceSpacing.xxs)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        .accessibilityIdentifier("tradeRooms.broadcast.video.chatMini")
        .accessibilityLabel("Live stream playing")
        .transition(
            .scale(scale: 0.92, anchor: .topTrailing)
                .combined(with: .opacity)
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: coordinator.programVideoTrackRevision
        )
    }
}