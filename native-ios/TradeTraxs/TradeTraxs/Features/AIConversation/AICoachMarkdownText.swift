import SwiftUI

/// Full Markdown rendering for AI coach assistant replies (headings, lists, bold, paragraphs).
struct AICoachMarkdownText: View {
    let content: String
    var emphasis: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        let source = AIGeneratedTextNormalizer.normalize(content)
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(colors.primaryText)
                .tint(colors.accent)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .lineSpacing(4)
        } else {
            Text(source)
                .font(emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .lineSpacing(4)
        }
    }
}