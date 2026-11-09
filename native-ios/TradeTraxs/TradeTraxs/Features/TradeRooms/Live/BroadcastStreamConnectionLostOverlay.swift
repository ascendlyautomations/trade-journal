import SwiftUI

struct BroadcastStreamConnectionLostOverlay: View {
    let notice: BroadcastStreamConnectionLostNotice
    var onRetry: () -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: ExperienceSpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(colors.warning)
                    .accessibilityHidden(true)

                Text("Connection lost")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("We lost the connection to this livestream. You can try again.")
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ExperienceButton(title: "Retry", kind: .primary, action: onRetry)
                ExperienceButton(title: "Close", kind: .secondary, action: onClose)
                    .padding(.top, ExperienceSpacing.xxs)
            }
            .padding(ExperienceSpacing.lg)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .fill(colors.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                    .strokeBorder(colors.separator.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, y: 12)
            .padding(ExperienceSpacing.lg)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

extension View {
    func broadcastStreamConnectionLostOverlay(
        notice: BroadcastStreamConnectionLostNotice?,
        onRetry: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        overlay {
            if let notice {
                BroadcastStreamConnectionLostOverlay(notice: notice, onRetry: onRetry, onClose: onClose)
                    .zIndex(10_001)
            }
        }
        .animation(.snappy(duration: 0.28), value: notice?.id)
    }
}
