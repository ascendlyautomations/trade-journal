import SwiftUI

/// Two-line clamp with inline `… more` / ` less` for dashboard insight and commentary copy.
struct DashboardExpandableInsightText: View {
    let text: String
    var typography: TypographyRole = .caption
    var textColor: Color?
    var lineLimit: Int = 2
    var accessibilityIdentifier: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var layoutWidth: CGFloat = 0

    private var resolvedColor: Color {
        textColor ?? colors.secondaryText
    }

    /// Fade behind `… more` so system tail truncation stays hidden on cards.
    private var fadeBase: Color {
        colors.surfacePrimary
    }

    private var shouldClampCollapsed: Bool {
        !isExpanded && (isTruncated || layoutWidth <= 1)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { layoutWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        layoutWidth = width
                    }
                    .onChange(of: dynamicTypeSize) { _, _ in
                        layoutWidth = geo.size.width
                    }
            }
        }
        .background {
            if layoutWidth > 1 {
                ExpandableInsightTextOverflowDetector(
                    text: text,
                    typography: typography,
                    color: resolvedColor,
                    lineLimit: lineLimit,
                    width: layoutWidth
                ) { truncated in
                    if isTruncated != truncated {
                        isTruncated = truncated
                    }
                }
                .id(dynamicTypeSize)
            }
        }
        .onChange(of: text) { _, _ in
            isExpanded = false
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            isExpanded = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }

    private var collapsedBody: some View {
        styledText
            .lineLimit(shouldClampCollapsed ? lineLimit : nil)
            .overlay(alignment: .bottomTrailing) {
                if isTruncated {
                    moreControl
                }
            }
    }

    private var expandedBody: some View {
        Text(expandedAttributed)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { _ in
                withAnimation(ExperienceMotion.selection) {
                    isExpanded = false
                }
                return .handled
            })
    }

    private var expandedAttributed: AttributedString {
        var body = AttributedString(text)
        var bodyStyle = AttributeContainer()
        bodyStyle.font = ExperienceTypography.font(typography)
        bodyStyle.foregroundColor = resolvedColor
        body.mergeAttributes(bodyStyle)

        var less = AttributedString(" less")
        var lessStyle = AttributeContainer()
        lessStyle.font = ExperienceTypography.font(typography).weight(.semibold)
        lessStyle.foregroundColor = colors.accent
        lessStyle.link = Self.lessToggleURL
        less.mergeAttributes(lessStyle)
        body.append(less)
        return body
    }

    private static let lessToggleURL = URL(string: "dashboard-expandable-insight://less")

    private var styledText: some View {
        Text(text)
            .experienceStyle(typography, color: resolvedColor)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreControl: some View {
        Button {
            withAnimation(ExperienceMotion.selection) {
                isExpanded = true
            }
        } label: {
            Text("… more")
                .font(ExperienceTypography.font(typography).weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.leading, 10)
                .background(
                    LinearGradient(
                        colors: [fadeBase.opacity(0), fadeBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show more")
    }

}

// MARK: - Overflow detection (same modifiers as visible text)

private struct ExpandableInsightTextOverflowDetector: View {
    let text: String
    let typography: TypographyRole
    let color: Color
    let lineLimit: Int
    let width: CGFloat
    let onTruncated: (Bool) -> Void

    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(width: width, height: 0)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    probeText(lineLimit: lineLimit)
                        .frame(width: width, alignment: .leading)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ExpandableInsightLimitedHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }

                    probeText(lineLimit: nil)
                        .frame(width: width, alignment: .leading)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ExpandableInsightFullHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }
                }
                .hidden()
            }
            .onPreferenceChange(ExpandableInsightLimitedHeightKey.self) { limitedHeight = $0; report() }
            .onPreferenceChange(ExpandableInsightFullHeightKey.self) { fullHeight = $0; report() }
    }

    @ViewBuilder
    private func probeText(lineLimit: Int?) -> some View {
        if let lineLimit {
            Text(text)
                .experienceStyle(typography, color: color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(lineLimit)
        } else {
            Text(text)
                .experienceStyle(typography, color: color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func report() {
        guard limitedHeight > 0, fullHeight > 0 else { return }
        onTruncated(fullHeight > limitedHeight + 0.5)
    }
}

private struct ExpandableInsightLimitedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ExpandableInsightFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}