import SwiftUI

struct BroadcastProgramVideoPlaceholderOverlay: View {
    let presentation: BroadcastProgramVideoPlaceholderPresentation
    var compact: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
            VStack(spacing: compact ? ExperienceSpacing.xxs : ExperienceSpacing.sm) {
                if presentation.showsSpinner {
                    if compact {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        ExperienceLoadingSpinner(label: presentation.accessibilityLabel)
                            .tint(.white)
                    }
                }
                if !compact {
                    Text(presentation.title)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, ExperienceSpacing.md)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("tradeRooms.broadcast.video.placeholder")
    }
}