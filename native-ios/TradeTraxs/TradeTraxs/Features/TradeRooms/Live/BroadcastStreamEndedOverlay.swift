import SwiftUI

/// App-scoped stream-ended dialog (shown from ``MainTabShellView`` while on any tab).
struct BroadcastStreamEndedOverlay: View {
    let notice: BroadcastStreamEndedNotice
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* require explicit Close */ }

            VStack(spacing: ExperienceSpacing.md) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                Text("Stream Ended")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("This livestream has ended.")
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ExperienceButton(title: "Close", kind: .primary, action: onClose)
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
    func broadcastStreamEndedOverlay(
        notice: BroadcastStreamEndedNotice?,
        onClose: @escaping () -> Void
    ) -> some View {
        overlay {
            if let notice {
                BroadcastStreamEndedOverlay(notice: notice, onClose: onClose)
                    .zIndex(10_000)
            }
        }
        .animation(.snappy(duration: 0.28), value: notice?.id)
    }
}
