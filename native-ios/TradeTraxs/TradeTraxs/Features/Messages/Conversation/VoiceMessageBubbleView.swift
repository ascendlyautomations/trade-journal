import SwiftUI

struct VoiceMessageBubbleView: View {
    let messageID: MessageID
    let audioReference: MediaReference
    let durationSeconds: TimeInterval?
    let isOutgoing: Bool

    @ObservedObject private var playback = VoiceMessagePlaybackController.shared
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Button(action: togglePlayback) {
                Image(systemName: playButtonSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOutgoing ? Color.white : colors.accent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActiveAndPlaying ? "Pause voice message" : "Play voice message")

            waveform
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isActive else { return }
                            let progress = value.location.x / max(waveformWidth, 1)
                            playback.scrub(messageID: messageID, progress: Double(progress))
                        }
                )

            Text(displayDuration)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : colors.secondaryText)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs + 2)
        .frame(minWidth: 180, maxWidth: 240)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOutgoing ? AnyShapeStyle(colors.accent) : AnyShapeStyle(colors.fillSecondary))
        }
        .accessibilityIdentifier(isOutgoing ? "conversation.bubble.voice.outgoing" : "conversation.bubble.voice.incoming")
    }

    private var isActive: Bool {
        playback.activeMessageID == messageID
    }

    private var isActiveAndPlaying: Bool {
        isActive && playback.isPlaying
    }

    private var playButtonSymbol: String {
        isActiveAndPlaying ? "pause.fill" : "play.fill"
    }

    private var resolvedDuration: TimeInterval {
        if isActive, playback.duration > 0 {
            return playback.duration
        }
        return durationSeconds ?? 0
    }

    private var displayDuration: String {
        let value = isActive ? playback.currentTime : resolvedDuration
        return VoiceMessageSupport.formatDuration(value)
    }

    private var progress: Double {
        guard isActive, resolvedDuration > 0 else { return 0 }
        return min(max(playback.currentTime / resolvedDuration, 0), 1)
    }

    private let waveformWidth: CGFloat = 120

    private var waveform: some View {
        let heights = VoiceMessageSupport.waveformHeights(seed: messageID.rawValue)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                let barProgress = Double(index + 1) / Double(heights.count)
                Capsule()
                    .fill(barColor(filled: barProgress <= progress))
                    .frame(width: 3, height: 8 + height * 16)
            }
        }
        .frame(width: waveformWidth, height: 28)
    }

    private func barColor(filled: Bool) -> Color {
        if isOutgoing {
            return filled ? Color.white : Color.white.opacity(0.35)
        }
        return filled ? colors.accent : colors.accent.opacity(0.25)
    }

    private func togglePlayback() {
        guard let url = resolvedPlaybackURL else { return }
        playback.toggle(
            messageID: messageID,
            remoteURL: url,
            knownDuration: durationSeconds
        )
    }

    private var resolvedPlaybackURL: URL? {
        if let url = URL(string: audioReference.id), url.scheme != nil {
            return url
        }
        return URL(string: audioReference.id)
    }
}
