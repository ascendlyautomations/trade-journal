import SwiftUI

/// Modal shown when OBS ingress reports encoder readiness during private prep (no logo; mirrors stream-ended chrome).
struct BroadcastObsConnectedOverlay: View {
    let onStartStream: () -> Void
    let onNotYet: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* require explicit choice */ }

            VStack(spacing: ExperienceSpacing.md) {
                Text("OBS Connected")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colors.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Your OBS encoder is connected. Ready to start streaming?")
                    .font(ExperienceTypography.body)
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: ExperienceSpacing.sm) {
                    ExperienceButton(title: "Start Stream", kind: .primary, action: onStartStream)
                        .padding(.top, ExperienceSpacing.xxs)

                    Button(action: onNotYet) {
                        Text("Not Yet")
                            .font(ExperienceTypography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, ExperienceSpacing.md)
                            .padding(.vertical, ExperienceSpacing.sm)
                            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                            .background(colors.fillSecondary)
                            .foregroundStyle(colors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous))
                    }
                    .buttonStyle(.experiencePlain)
                }
                .frame(maxWidth: .infinity)
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
        .accessibilityIdentifier("broadcast.obsConnected.prompt")
    }
}

extension View {
    func broadcastObsConnectedOverlay(
        isPresented: Bool,
        onStartStream: @escaping () -> Void,
        onNotYet: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented {
                BroadcastObsConnectedOverlay(
                    onStartStream: onStartStream,
                    onNotYet: onNotYet
                )
                .zIndex(10_000)
            }
        }
        .animation(.snappy(duration: 0.28), value: isPresented)
    }
}