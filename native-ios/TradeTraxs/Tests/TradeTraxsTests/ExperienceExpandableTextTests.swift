import XCTest
@testable import TradeTraxs

final class ExperienceExpandableTextTests: XCTestCase {
    func testShortTextDoesNotReserveMoreSuffix() {
        let width: CGFloat = 280
        let presentation = ExperienceExpandableTextMeasurement.collapsedPresentation(
            text: "Two short lines fit fine.",
            width: width,
            role: .caption,
            maxLines: 2
        )
        XCTAssertFalse(presentation.showsMore)
        XCTAssertEqual(presentation.visibleBody, "Two short lines fit fine.")
    }

    func testLongTextFitsCollapsedLinesWithInlineMoreSuffix() {
        let width: CGFloat = 260
        let long = String(
            repeating: "Held through the open drive with disciplined sizing and patience. ",
            count: 4
        )
        let presentation = ExperienceExpandableTextMeasurement.collapsedPresentation(
            text: long,
            width: width,
            role: .body,
            maxLines: 2,
            moreSuffix: ExperienceExpandableTextMeasurement.defaultMoreSuffix
        )
        XCTAssertTrue(presentation.showsMore)
        XCTAssertFalse(presentation.visibleBody.isEmpty)

        let bodyFont = ExperienceExpandableTextMeasurement.uiFont(for: .body)
        let suffixFont = ExperienceExpandableTextMeasurement.uiFont(for: .body, weight: .semibold)
        let composed = presentation.visibleBody + ExperienceExpandableTextMeasurement.defaultMoreSuffix
        let lineCount = ExperienceExpandableTextTests.lineCount(
            for: composed,
            width: width,
            bodyFont: bodyFont,
            suffixFont: suffixFont,
            suffix: ExperienceExpandableTextMeasurement.defaultMoreSuffix
        )
        XCTAssertLessThanOrEqual(lineCount, 2)
        XCTAssertTrue(long.hasPrefix(presentation.visibleBody))
    }

    func testOverflowDetectionMatchesPresentation() {
        let width: CGFloat = 200
        let text = String(repeating: "Alpha bravo charlie delta echo. ", count: 5)
        let overflows = ExperienceExpandableTextMeasurement.overflows(
            text: text,
            width: width,
            role: .footnote,
            maxLines: 2
        )
        let presentation = ExperienceExpandableTextMeasurement.collapsedPresentation(
            text: text,
            width: width,
            role: .footnote,
            maxLines: 2
        )
        XCTAssertEqual(overflows, presentation.showsMore)
        XCTAssertTrue(overflows)
    }

    private static func lineCount(
        for string: String,
        width: CGFloat,
        bodyFont: UIFont,
        suffixFont: UIFont,
        suffix: String
    ) -> Int {
        let visibleCount = string.count - suffix.count
        let visible = String(string.prefix(visibleCount))
        let composed = NSMutableAttributedString(string: visible, attributes: [.font: bodyFont])
        composed.append(NSAttributedString(string: suffix, attributes: [.font: suffixFont]))
        let storage = NSTextStorage(attributedString: composed)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
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
}