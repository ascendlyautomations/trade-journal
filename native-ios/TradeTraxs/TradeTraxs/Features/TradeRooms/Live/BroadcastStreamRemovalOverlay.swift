import SwiftUI

/// Shown when the user was removed from a livestream by a moderator (stream may still be live).
struct BroadcastStreamRemovalOverlay: View {
    let notice: BroadcastStreamRemovalNotice
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* require explicit Close */ }

            VStack(spacing: ExperienceSpacing.md) {
                Image(systemName: notice.blocked ? "hand.raised.slash.fill" : "person.fill.xmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(notice.blocked ? colors.error : colors.warning)
                    .accessibilityHidden(true)

                Text(notice.blocked ? "Removed and blocked" : "Removed from stream")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(
                    notice.blocked
                        ? "You were removed from this livestream and blocked from rejoining for this session."
                        : "You were removed from this livestream by the host."
                )
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                ExperienceButton(title: "OK", kind: .primary, action: onClose)
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
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func broadcastStreamRemovalOverlay(
        notice: BroadcastStreamRemovalNotice?,
        onClose: @escaping () -> Void
    ) -> some View {
        overlay {
            if let notice {
                BroadcastStreamRemovalOverlay(notice: notice, onClose: onClose)
                    .zIndex(10_001)
            }
        }
        .animation(.snappy(duration: 0.28), value: notice?.id)
    }
}
