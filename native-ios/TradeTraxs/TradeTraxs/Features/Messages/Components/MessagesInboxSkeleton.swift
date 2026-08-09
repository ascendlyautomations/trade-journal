import SwiftUI

struct MessagesInboxSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: ExperienceSpacing.sm) {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 52, height: 52)
                        .overlay(ExperienceSkeleton(height: 52, cornerRadius: 26))
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ExperienceSkeleton(height: 14, cornerRadius: ExperienceRadius.xs)
                            .frame(maxWidth: 140)
                        ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: ExperienceSpacing.sm)
                    ExperienceSkeleton(height: 12, cornerRadius: ExperienceRadius.xs)
                        .frame(width: 28)
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
        }
        .padding(.top, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}
