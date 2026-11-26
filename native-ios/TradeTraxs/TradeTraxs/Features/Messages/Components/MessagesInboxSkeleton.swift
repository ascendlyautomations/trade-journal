import SwiftUI

struct MessagesInboxSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                HStack(spacing: MessagesInboxLayout.rowHorizontalSpacing) {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: MessagesInboxLayout.avatarSide, height: MessagesInboxLayout.avatarSide)
                        .overlay(
                            ExperienceSkeleton(
                                height: MessagesInboxLayout.avatarSide,
                                cornerRadius: MessagesInboxLayout.avatarSide / 2
                            )
                        )
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
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, MessagesInboxLayout.rowVerticalPadding)
                if index < 7 {
                    ExperienceDivider()
                        .padding(.leading, ExperienceSpacing.md + MessagesInboxLayout.avatarSide + MessagesInboxLayout.rowHorizontalSpacing)
                }
            }
        }
        .padding(.top, MessagesInboxLayout.listTopContentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}