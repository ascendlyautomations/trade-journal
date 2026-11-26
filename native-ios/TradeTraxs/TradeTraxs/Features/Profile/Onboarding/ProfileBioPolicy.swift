import SwiftUI
import UIKit

/// Profile bio line limit shared by onboarding and Settings (manual newlines + wrapped display).
nonisolated enum ProfileBioPolicy {
    static let maximumLines = 3

    /// Matches ``ProfileHeaderView`` bio text (subheadline + 3pt line spacing).
    static let displayLineSpacing: CGFloat = 3

    /// Profile header horizontal inset: ``ProfileView`` uses ``SpacingToken/lg``.
    static let profileHorizontalInset: CGFloat = SpacingToken.lg.value * 2

    enum EditDecision: Equatable {
        case accept
        case reject
        case apply(String)
    }

    static func referenceContentWidth(screenWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
        max(120, screenWidth - profileHorizontalInset)
    }

    /// Upper bound on UTF-16 length when filling the bio with average-width characters at the profile display width.
    static func maximumAllowedCharacterCount(contentWidth: CGFloat = referenceContentWidth()) -> Int {
        var low = 0
        var high = 600
        while low < high {
            let mid = (low + high + 1) / 2
            let probe = String(repeating: "n", count: mid)
            if visibleLineCount(probe, contentWidth: contentWidth) <= maximumLines {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    static func characterCount(for text: String) -> Int {
        (text as NSString).length
    }

    static func characterCounterLabel(for text: String, contentWidth: CGFloat = referenceContentWidth()) -> String {
        let current = characterCount(for: text)
        let max = maximumAllowedCharacterCount(contentWidth: contentWidth)
        return "\(current)/\(max)"
    }

    static func lineCount(_ value: String) -> Int {
        normalizeLineEndings(value).split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func visibleLineCount(_ value: String, contentWidth: CGFloat) -> Int {
        let trimmed = value as NSString
        guard trimmed.length > 0 else { return 0 }

        let font = displayUIFont()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = displayLineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]

        let storage = NSTextStorage(attributedString: NSAttributedString(string: trimmed as String, attributes: attributes))
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return 0 }

        var lines = 0
        var glyphIndex = glyphRange.location
        let limit = NSMaxRange(glyphRange)
        while glyphIndex < limit {
            var lineRange = NSRange()
            _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            lines += 1
            glyphIndex = NSMaxRange(lineRange)
        }
        return lines
    }

    /// Input-level gate: newline cap, then wrapped display cap (paste included).
    static func editDecision(
        current: String,
        range: NSRange,
        replacement: String,
        contentWidth: CGFloat = referenceContentWidth()
    ) -> EditDecision {
        let nsCurrent = current as NSString
        guard range.location <= nsCurrent.length,
              range.location + range.length <= nsCurrent.length
        else {
            return .reject
        }
        let proposed = nsCurrent.replacingCharacters(in: range, with: replacement) as String
        let capped = constrained(proposed, contentWidth: contentWidth)
        if capped == proposed {
            return .accept
        }
        if capped == current {
            return .reject
        }
        return .apply(capped)
    }

    /// Keeps the first ``maximumLines`` manual newlines, then trims so wrapped layout stays within three lines on profile.
    static func constrained(
        _ value: String,
        contentWidth: CGFloat = referenceContentWidth()
    ) -> String {
        let newlineCapped = constrainedManualNewlines(value)
        if visibleLineCount(newlineCapped, contentWidth: contentWidth) <= maximumLines {
            return newlineCapped
        }
        return truncateToVisibleLineLimit(newlineCapped, contentWidth: contentWidth)
    }

    /// Line-capped bio ready to save. Empty input stays empty/nil, matching existing trim behavior.
    static func persisted(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = constrained(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func binding(
        _ source: Binding<String>,
        contentWidth: CGFloat = referenceContentWidth()
    ) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                let next = constrained(newValue, contentWidth: contentWidth)
                guard source.wrappedValue != next else { return }
                source.wrappedValue = next
            }
        )
    }

    // MARK: - Private

    private static func constrainedManualNewlines(_ value: String) -> String {
        let normalized = normalizeLineEndings(value)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maximumLines else { return normalized }
        return lines.prefix(maximumLines).joined(separator: "\n")
    }

    private static func truncateToVisibleLineLimit(_ text: String, contentWidth: CGFloat) -> String {
        let ns = text as NSString
        guard ns.length > 0 else { return text }

        var low = 0
        var high = ns.length
        var best = ""

        while low <= high {
            let mid = (low + high) / 2
            let prefix = ns.substring(to: mid)
            if visibleLineCount(prefix, contentWidth: contentWidth) <= maximumLines {
                best = prefix
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    private static func displayUIFont() -> UIFont {
        UIFont.preferredFont(forTextStyle: .subheadline)
    }

    private static func normalizeLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}