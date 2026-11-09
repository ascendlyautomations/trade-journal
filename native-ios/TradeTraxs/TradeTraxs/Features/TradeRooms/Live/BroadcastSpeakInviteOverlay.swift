import SwiftUI

/// App-scoped speak invitation (shown while in a Trade Room with an active livestream).
struct BroadcastSpeakInviteOverlay: View {
    let notice: BroadcastSpeakInviteNotice
    @Bindable var coordinator: RoomBroadcastCoordinator

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: ExperienceSpacing.md) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .accessibilityHidden(true)

                Text("You've Been Invited to Speak")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colors.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("The broadcaster invited you to join the conversation.")
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = coordinator.speakInviteActionError, !error.isEmpty {
                    Text(error)
                        .font(ExperienceTypography.caption)
                        .foregroundStyle(colors.error)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: ExperienceSpacing.xs) {
                    ExperienceButton(
                        title: coordinator.isBusy ? "Joining…" : "Accept & Join",
                        kind: .primary
                    ) {
                        Task { await coordinator.acceptSpeakInvitation() }
                    }
                    .disabled(coordinator.isBusy)

                    Button("Decline") {
                        Task { await coordinator.declineSpeakInvitation() }
                    }
                    .font(ExperienceTypography.body.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .disabled(coordinator.isBusy)
                }
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
    /// Tab-shell overlay when the broadcast viewer sheet is minimized (sheet is not presented).
    func broadcastSpeakInviteOverlay(coordinator: RoomBroadcastCoordinator) -> some View {
        overlay {
            if let notice = coordinator.speakInviteNotice, !coordinator.isViewerPresented {
                BroadcastSpeakInviteOverlay(notice: notice, coordinator: coordinator)
                    .zIndex(100_000)
            }
        }
        .animation(.snappy(duration: 0.28), value: coordinator.speakInviteNotice?.id)
    }
}
