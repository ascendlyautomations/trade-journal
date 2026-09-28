import SwiftUI

/// Shared channel post permission control — maps to `room_sections.allow_members_chat`.
struct RoomChannelPostingPermissionPicker: View {
    @Binding var allowMembersChat: Bool
    var isDisabled: Bool = false

    @Environment(\.themeColors) private var colors

    private var selected: RoomChannelPostingPermission {
        RoomChannelPostingPermission.from(allowMembersChat: allowMembersChat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("WHO CAN POST")
                .experienceStyle(.caption, color: colors.secondaryText)

            ForEach(RoomChannelPostingPermission.allCases, id: \.self) { option in
                Button {
                    allowMembersChat = option.allowMembersChat
                    ExperienceHaptics.play(.selection)
                } label: {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: selected == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == option ? colors.accent : colors.tertiaryText)
                        Text(option.summaryLabel)
                            .experienceStyle(.body, color: colors.primaryText)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
    }
}
