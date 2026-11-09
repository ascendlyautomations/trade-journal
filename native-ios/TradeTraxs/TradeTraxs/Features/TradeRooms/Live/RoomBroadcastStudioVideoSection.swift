import LiveKit
import SwiftUI

/// Shared 16:9 program video chrome (viewer + OBS manage stream).
struct RoomBroadcastStudioVideoSection: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Binding var isFullscreen: Bool
    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForDisplay,
                isFullscreen: false
            )
            .id(coordinator.programVideoTrackRevision)
            HStack(spacing: ExperienceSpacing.xs) {
                RoomBroadcastStreamPlaybackMuteButton(coordinator: coordinator)
                Button {
                    isFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Fullscreen")
            }
            .padding(ExperienceSpacing.sm)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// Local playback mute — does not affect the broadcast sent to other viewers.
struct RoomBroadcastStreamPlaybackMuteButton: View {
    @Bindable var coordinator: RoomBroadcastCoordinator

    var body: some View {
        Button {
            Task { await coordinator.toggleStreamPlaybackMute() }
        } label: {
            Image(systemName: coordinator.isStreamPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(coordinator.isStreamPlaybackMuted ? "Unmute stream" : "Mute stream")
    }
}
