import SwiftUI
import UIKit

/// UIKit text measurement for ``ExperienceExpandableText`` (Dynamic Type–aware, width-based).
nonisolated enum ExperienceExpandableTextMeasurement {
    static let defaultMoreSuffix = "...more"
    static let defaultLessSuffix = " less"

    struct CollapsedPresentation: Equatable, Sendable {
        var visibleBody: String
        var showsMore: Bool
    }

    static func collapsedPresentation(
        text: String,
        width: CGFloat,
        role: TypographyRole,
        maxLines: Int,
        moreSuffix: String = defaultMoreSuffix
    ) -> CollapsedPresentation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 1, maxLines > 0 else {
            return CollapsedPresentation(visibleBody: trimmed, showsMore: false)
        }

        let bodyFont = uiFont(for: role)
        let suffixFont = uiFont(for: role, weight: .semibold)

        if lineCount(
            for: trimmed,
            width: width,
            bodyFont: bodyFont,
            suffixFont: suffixFont,
            suffix: ""
        ) <= maxLines {
            return CollapsedPresentation(visibleBody: trimmed, showsMore: false)
        }

        let scalars = Array(trimmed)
        var low = 0
        var high = scalars.count

        while low < high {
            let mid = (low + high + 1) / 2
            let prefix = polishedPrefix(String(scalars.prefix(mid)))
            let candidate = prefix + moreSuffix
            if lineCount(
                for: candidate,
                width: width,
                bodyFont: bodyFont,
                suffixFont: suffixFont,
                suffix: moreSuffix
            ) <= maxLines {
                low = mid
            } else {
                high = mid - 1
            }
        }

        let visible = polishedPrefix(String(scalars.prefix(low)))
        return CollapsedPresentation(visibleBody: visible, showsMore: true)
    }

    static func overflows(
        text: String,
        width: CGFloat,
        role: TypographyRole,
        maxLines: Int
    ) -> Bool {
        collapsedPresentation(
            text: text,
            width: width,
            role: role,
            maxLines: maxLines
        ).showsMore
    }

    // MARK: - Fonts

    static func uiFont(for role: TypographyRole, weight: UIFont.Weight? = nil) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: uiTextStyle(for: role))
        let resolvedWeight = weight ?? uiWeight(for: role)
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.traits: [
                UIFontDescriptor.TraitKey.weight: resolvedWeight,
            ],
        ])
        let sized = UIFont(descriptor: descriptor, size: 0)
        return sized
    }

    // MARK: - Layout

    private static func lineCount(
        for string: String,
        width: CGFloat,
        bodyFont: UIFont,
        suffixFont: UIFont,
        suffix: String
    ) -> Int {
        let attributed = attributedString(
            body: string,
            suffixPortion: suffix,
            bodyFont: bodyFont,
            suffixFont: suffixFont
        )
        return lineCount(for: attributed, width: width)
    }

    private static func attributedString(
        body: String,
        suffixPortion: String,
        bodyFont: UIFont,
        suffixFont: UIFont
    ) -> NSAttributedString {
        guard !suffixPortion.isEmpty, body.hasSuffix(suffixPortion) else {
            return NSAttributedString(string: body, attributes: [.font: bodyFont])
        }
        let visibleCount = body.count - suffixPortion.count
        let visible = String(body.prefix(visibleCount))
        let composed = NSMutableAttributedString(string: visible, attributes: [.font: bodyFont])
        composed.append(
            NSAttributedString(string: suffixPortion, attributes: [.font: suffixFont])
        )
        return composed
    }

    private static func lineCount(for attributed: NSAttributedString, width: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: attributed)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var index = 0
        var lines = 0
        let glyphCount = manager.numberOfGlyphs
        while index < glyphCount {
            var effectiveRange = NSRange()
            _ = manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &effectiveRange)
            lines += 1
            index = NSMaxRange(effectiveRange)
        }
        return lines
    }

    private static func uiTextStyle(for role: TypographyRole) -> UIFont.TextStyle {
        switch role {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption, .metric: return .caption1
        case .caption2: return .caption2
        case .metricLarge: return .title2
        }
    }

    private static func uiWeight(for role: TypographyRole) -> UIFont.Weight {
        switch role {
        case .largeTitle, .title, .title2, .headline, .metricLarge:
            return .semibold
        case .title3, .metric:
            return .medium
        default:
            return .regular
        }
    }

    private static func polishedPrefix(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let breakIndex = trimmed.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            let tail = trimmed[trimmed.index(after: breakIndex)...]
            if tail.count <= 8, trimmed.distance(from: trimmed.startIndex, to: breakIndex) > 8 {
                trimmed = String(trimmed[..<breakIndex])
            }
        }
        return trimmed.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}