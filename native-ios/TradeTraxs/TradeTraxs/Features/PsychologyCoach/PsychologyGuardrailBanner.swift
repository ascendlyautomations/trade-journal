import SwiftUI

struct PsychologyGuardrailBanner: View {
    let notice: PsychologyGuardrailNotice
    var onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(notice.message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.warning.opacity(0.35), lineWidth: 1)
        }
        .accessibilityIdentifier("psychologyGuardrail.\(notice.kind.rawValue)")
    }
}
