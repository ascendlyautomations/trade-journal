import SwiftUI

/// Full-width Go Live + End Stream controls for OBS preparing / manage surfaces.
struct TradeRoomObsBroadcastBottomActions: View {
    let showsGoLive: Bool
    let goLiveEnabled: Bool
    let endStreamEnabled: Bool
    let onGoLive: () -> Void
    let onEndStream: () -> Void
    /// When false, the parent supplies the opaque page chrome (Preparing OBS inset footer).
    var embedsBarBackground: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            if showsGoLive {
                ExperienceButton(
                    title: "Go Live",
                    icon: .play,
                    kind: .primary,
                    isEnabled: goLiveEnabled,
                    keepsEnabledAppearanceWhenDisabled: true,
                    action: onGoLive
                )
                .accessibilityIdentifier("tradeRooms.broadcast.goLive")
            }

            Button(action: onEndStream) {
                HStack(spacing: ExperienceSpacing.xs) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("End Stream")
                        .font(ExperienceTypography.headline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm)
                .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                .foregroundStyle(colors.error)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .fill(colors.error.opacity(0.12))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .stroke(colors.error.opacity(0.22), lineWidth: ExperienceBorder.thin)
                }
            }
            .buttonStyle(.experiencePlain)
            .disabled(!endStreamEnabled)
            .opacity(endStreamEnabled ? 1 : ExperienceOpacity.disabled)
            .accessibilityIdentifier("tradeRooms.broadcast.endStream")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, embedsBarBackground ? ExperienceSpacing.sm : 0)
        .padding(.bottom, embedsBarBackground ? ExperienceSpacing.md : 0)
        .background {
            if embedsBarBackground {
                colors.primaryBackground
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: -4)
            }
        }
    }
}