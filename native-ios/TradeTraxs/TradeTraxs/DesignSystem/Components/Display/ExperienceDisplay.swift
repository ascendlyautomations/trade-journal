import SwiftUI

struct ExperienceDivider: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.divider)
            .frame(height: ExperienceBorder.hairline)
            .accessibilityHidden(true)
    }
}

struct ExperienceAvatar: View {
    var initials: String = ""
    var image: Image? = nil
    var size: CGFloat = 40

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(colors.fillPrimary)
            Text(initials)
                .experienceStyle(.caption, color: colors.secondaryText)
                .opacity(image == nil ? 1 : 0)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: image == nil
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(colors.border, lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityLabel(Text(initials.isEmpty ? "Avatar" : initials))
        .accessibilityIdentifier("avatar")
    }
}

struct ExperienceCard<Content: View>: View {
    var elevated: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        content()
            .padding(ExperienceSpacing.md)
            .experienceSurface(
                elevated ? .elevatedCard : .card,
                cornerRadius: ExperienceRadius.card,
                elevation: elevated ? .low : .flat
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(colors.border.opacity(ExperienceOpacity.subtle), lineWidth: ExperienceBorder.hairline)
            }
    }
}

struct ExperienceSectionContainer<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            header()
            content()
        }
        .padding(ExperienceSpacing.md)
        .experienceSurface(.groupedBackground, cornerRadius: ExperienceRadius.lg)
    }
}

struct ExperienceListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            leading()
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.body, color: colors.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            trailing()
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("list.row.\(title)")
    }
}

extension ExperienceListRow where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
    }
}
