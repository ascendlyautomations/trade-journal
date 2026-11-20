import LiveKit
import SwiftUI

/// Shared 16:9 program video chrome (viewer + OBS manage stream).
struct RoomBroadcastStudioVideoSection: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Binding var isFullscreen: Bool
    /// Viewer sheet while typing: short live strip; does not recreate the video renderer.
    var isCompactForChatComposer: Bool = false
    @Environment(\.themeColors) private var colors

    private var compactVideoHeight: CGFloat { 56 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForExpandedViewer,
                isFullscreen: false
            )
            .id(coordinator.programVideoTrackRevision)
            HStack(spacing: ExperienceSpacing.xs) {
                RoomBroadcastStreamPlaybackMuteButton(coordinator: coordinator)
                if !isCompactForChatComposer {
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
            }
            .padding(isCompactForChatComposer ? ExperienceSpacing.xs : ExperienceSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompactForChatComposer ? compactVideoHeight : nil)
        .aspectRatio(isCompactForChatComposer ? nil : 16 / 9, contentMode: .fit)
        .clipped()
        .accessibilityIdentifier(
            isCompactForChatComposer
                ? "tradeRooms.broadcast.video.compact"
                : "tradeRooms.broadcast.video.expanded"
        )
    }
}

/// Opens livestream playback settings. Does not publish or change the host microphone.
struct RoomBroadcastStreamPlaybackMuteButton: View {
    @Bindable var coordinator: RoomBroadcastCoordinator

    var body: some View {
        RoomBroadcastAudioControl(coordinator: coordinator, style: .overlay)
    }
}

enum RoomBroadcastAudioControlStyle {
    case toolbar
    case bar
    case fullscreen
    case overlay
}

struct RoomBroadcastAudioControl: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    var style: RoomBroadcastAudioControlStyle

    @State private var showsSettings = false
    @Environment(\.themeColors) private var colors

    private var speakerSymbol: String {
        coordinator.isStreamPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    var body: some View {
        Button {
            showsSettings = true
        } label: {
            controlLabel
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Audio")
        .accessibilityValue(coordinator.isStreamPlaybackMuted ? "Muted" : "Unmuted")
        .accessibilityIdentifier("tradeRooms.broadcast.audio")
        .popover(isPresented: $showsSettings) {
            RoomBroadcastAudioSettings(coordinator: coordinator)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var controlLabel: some View {
        switch style {
        case .toolbar:
            VStack(spacing: 2) {
                Image(systemName: speakerSymbol)
                    .font(.system(size: 18, weight: .semibold))
                Text("Audio")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(colors.primaryText)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
        case .bar:
            Image(systemName: speakerSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 36, height: 36)
        case .fullscreen:
            Image(systemName: speakerSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.white.opacity(0.15)))
        case .overlay:
            Image(systemName: speakerSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
    }
}

private struct RoomBroadcastAudioSettings: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    private var percent: Int {
        Int((coordinator.streamPlaybackGain * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack {
                Text("Volume")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text("\(percent)%")
                    .monospacedDigit()
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            }
            Slider(
                value: Binding(
                    get: { coordinator.streamPlaybackGain },
                    set: { coordinator.setStreamPlaybackGain($0) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Stream volume")
            .accessibilityValue("\(percent) percent")

            Toggle(
                isOn: Binding(
                    get: { coordinator.isStreamPlaybackMuted },
                    set: { muted in
                        guard muted != coordinator.isStreamPlaybackMuted else { return }
                        Task { await coordinator.toggleStreamPlaybackMute() }
                    }
                )
            ) {
                Text(coordinator.isStreamPlaybackMuted ? "Unmute" : "Mute")
                    .experienceStyle(.subheadline, color: colors.primaryText)
            }
            .tint(colors.accent)
        }
        .padding(ExperienceSpacing.md)
        .frame(width: 260, alignment: .leading)
        .background(colors.elevatedSurface)
        .presentationBackground(colors.elevatedSurface)
        .accessibilityIdentifier("tradeRooms.broadcast.audioSettings")
    }
}
