import SwiftUI

/// Collapsed body is limited to `collapsedLineLimit` lines with inline `...more` when text overflows.
struct ExperienceExpandableText: View {
    enum VisualStyle: Equatable, Sendable {
        case standard
        case clipsOverlay
    }

    let text: String
    var typography: TypographyRole = .caption
    var textColor: Color?
    var moreColor: Color?
    var collapsedLineLimit: Int = 2
    var moreSuffix: String = ExperienceExpandableTextMeasurement.defaultMoreSuffix
    var lessSuffix: String = ExperienceExpandableTextMeasurement.defaultLessSuffix
    var visualStyle: VisualStyle = .standard
    var accessibilityIdentifier: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false
    @State private var layoutWidth: CGFloat = 0
    @State private var presentation = ExperienceExpandableTextMeasurement.CollapsedPresentation(
        visibleBody: "",
        showsMore: false
    )

    private var resolvedTextColor: Color {
        switch visualStyle {
        case .clipsOverlay:
            return textColor ?? .white
        case .standard:
            return textColor ?? colors.secondaryText
        }
    }

    private var resolvedMoreColor: Color {
        switch visualStyle {
        case .clipsOverlay:
            return moreColor ?? .white.opacity(0.9)
        case .standard:
            return moreColor ?? colors.accent
        }
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else if presentation.showsMore {
                collapsedOverflowBody
            } else {
                plainBody
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { layoutWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        layoutWidth = width
                    }
            }
        }
        .onChange(of: layoutWidth) { _, _ in recomputePresentation() }
        .onChange(of: text) { _, _ in
            isExpanded = false
            recomputePresentation()
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            isExpanded = false
            recomputePresentation()
        }
        .onChange(of: collapsedLineLimit) { _, _ in recomputePresentation() }
        .onAppear { recomputePresentation() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .modifier(OptionalExpandableTextAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }

    private var plainBody: some View {
        styledText(text)
            .lineLimit(collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var collapsedOverflowBody: some View {
        Text(collapsedAttributed)
            .lineLimit(collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(ExpandableTextClipsOverlayShadow(style: visualStyle))
            .environment(\.openURL, OpenURLAction { url in
                if url == Self.moreToggleURL {
                    withAnimation(ExperienceMotion.selection) {
                        isExpanded = true
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private var expandedBody: some View {
        Text(expandedAttributed)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(ExpandableTextClipsOverlayShadow(style: visualStyle))
            .environment(\.openURL, OpenURLAction { url in
                if url == Self.lessToggleURL {
                    withAnimation(ExperienceMotion.selection) {
                        isExpanded = false
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private var collapsedAttributed: AttributedString {
        var body = AttributedString(presentation.visibleBody)
        var bodyStyle = AttributeContainer()
        bodyStyle.font = ExperienceTypography.font(typography)
        bodyStyle.foregroundColor = resolvedTextColor
        body.mergeAttributes(bodyStyle)

        var more = AttributedString(moreSuffix)
        var moreStyle = AttributeContainer()
        moreStyle.font = ExperienceTypography.font(typography).weight(.semibold)
        moreStyle.foregroundColor = resolvedMoreColor
        moreStyle.link = Self.moreToggleURL
        more.mergeAttributes(moreStyle)
        return body + more
    }

    private var expandedAttributed: AttributedString {
        var body = AttributedString(text)
        var bodyStyle = AttributeContainer()
        bodyStyle.font = ExperienceTypography.font(typography)
        bodyStyle.foregroundColor = resolvedTextColor
        body.mergeAttributes(bodyStyle)

        var less = AttributedString(lessSuffix)
        var lessStyle = AttributeContainer()
        lessStyle.font = ExperienceTypography.font(typography).weight(.semibold)
        lessStyle.foregroundColor = resolvedMoreColor
        lessStyle.link = Self.lessToggleURL
        less.mergeAttributes(lessStyle)
        return body + less
    }

    @ViewBuilder
    private func styledText(_ value: String) -> some View {
        switch visualStyle {
        case .standard:
            Text(value)
                .experienceStyle(typography, color: resolvedTextColor)
        case .clipsOverlay:
            Text(value)
                .font(ExperienceTypography.font(typography))
                .foregroundStyle(resolvedTextColor)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    private func recomputePresentation() {
        guard layoutWidth > 1 else { return }
        let next = ExperienceExpandableTextMeasurement.collapsedPresentation(
            text: text,
            width: layoutWidth,
            role: typography,
            maxLines: collapsedLineLimit,
            moreSuffix: moreSuffix
        )
        if next != presentation {
            presentation = next
        }
        if !next.showsMore, isExpanded {
            isExpanded = false
        }
    }

    private static let moreToggleURL = URL(string: "tradetraxs-expandable-text://more")
    private static let lessToggleURL = URL(string: "tradetraxs-expandable-text://less")
}

private struct ExpandableTextClipsOverlayShadow: ViewModifier {
    let style: ExperienceExpandableText.VisualStyle

    func body(content: Content) -> some View {
        if style == .clipsOverlay {
            content.shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        } else {
            content
        }
    }
}

private struct OptionalExpandableTextAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}