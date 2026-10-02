import SwiftUI

/// Multi-slide segment indicators — inset matches author row / overflow menu.
struct StorySlideProgressStrip: View {
    let slideCount: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            ForEach(0..<slideCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(index <= activeIndex ? 0.95 : 0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Story \(activeIndex + 1) of \(slideCount)")
        .accessibilityIdentifier("feed.story.progress")
    }
}
