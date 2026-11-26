import SwiftUI

struct MessagesInboxSkeleton: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: MessagesInboxLayout.rowHorizontalSpacing) {
                        ExperienceSkeleton(
                            height: MessagesInboxLayout.avatarSide,
                            cornerRadius: ExperienceRadius.md
                        )
                        .frame(width: MessagesInboxLayout.avatarSide, height: MessagesInboxLayout.avatarSide)
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                            ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                                .frame(maxWidth: 140)
                            ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                                .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: ExperienceSpacing.xs)
                        ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                            .frame(width: 28)
                    }
                    .padding(.vertical, MessagesInboxLayout.rowVerticalPadding)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listSectionSpacing(MessagesInboxLayout.sectionSpacing)
        .experienceInsetGroupedListStyle(pageBackground: false)
        .scrollDisabled(true)
        .accessibilityHidden(true)
    }
}