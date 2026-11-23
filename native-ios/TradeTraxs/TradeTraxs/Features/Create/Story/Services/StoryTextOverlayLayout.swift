import CoreGraphics
import SwiftUI
import UIKit

/// Single layout model for story text in the editor preview, bitmap renderer, and playback overlay.
enum StoryTextOverlayLayout {
  static let minBaseFontSize: CGFloat = 18
  static let fontWidthRatio: CGFloat = 0.065
  static let maxTextWidthRatio: CGFloat = 0.82
  static let backgroundPaddingHorizontal: CGFloat = 6
  static let backgroundPaddingVertical: CGFloat = 3
  static let backgroundCornerRadius: CGFloat = 8

  static func baseFontSize(canvasWidth: CGFloat) -> CGFloat {
    max(minBaseFontSize, canvasWidth * fontWidthRatio)
  }

  static func fontSize(canvasWidth: CGFloat, scale: CGFloat) -> CGFloat {
    baseFontSize(canvasWidth: canvasWidth) * scale
  }

  static func maxTextWidth(canvasWidth: CGFloat) -> CGFloat {
    canvasWidth * maxTextWidthRatio
  }

  struct MeasuredBlock: Equatable {
    var textSize: CGSize
    var backgroundSize: CGSize

    var contentSize: CGSize {
      backgroundSize == .zero ? textSize : backgroundSize
    }
  }

  struct CanvasPlacement: Equatable {
    /// Anchor in canvas space (matches persisted normalized center).
    var anchorCenter: CGPoint
    /// Text + optional background plate, centered on `anchorCenter`.
    var contentFrame: CGRect
    var textFrame: CGRect
    var backgroundFrame: CGRect?
  }

  static func measuredBlock(for overlay: StoryTextOverlay, canvasWidth: CGFloat) -> MeasuredBlock {
    let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let fontSize = Self.fontSize(canvasWidth: canvasWidth, scale: overlay.scale)
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let paragraph = paragraphStyle(for: overlay.alignment)

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .paragraphStyle: paragraph,
    ]
    let text = trimmed.isEmpty ? " " : trimmed
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let maxWidth = maxTextWidth(canvasWidth: canvasWidth)
    let textBounds = attributed.boundingRect(
      with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )

    // Tight ink box — never expand to the wrap width unless the glyphs actually use it.
    let textSize = CGSize(
      width: max(ceil(textBounds.width), 1),
      height: max(ceil(textBounds.height), 1)
    )
    guard overlay.backgroundStyle != .none else {
      return MeasuredBlock(textSize: textSize, backgroundSize: .zero)
    }

    let plate = CGSize(
      width: textSize.width + backgroundPaddingHorizontal * 2,
      height: textSize.height + backgroundPaddingVertical * 2
    )
    return MeasuredBlock(textSize: textSize, backgroundSize: plate)
  }

  static func placement(for overlay: StoryTextOverlay, canvasSize: CGSize) -> CanvasPlacement {
    let anchor = CGPoint(
      x: overlay.normalizedCenter.x * canvasSize.width,
      y: overlay.normalizedCenter.y * canvasSize.height
    )
    let measured = measuredBlock(for: overlay, canvasWidth: canvasSize.width)
    let contentSize = measured.contentSize

    let contentOrigin = CGPoint(
      x: anchor.x - contentSize.width / 2,
      y: anchor.y - contentSize.height / 2
    )
    let contentFrame = CGRect(origin: contentOrigin, size: contentSize)

    let textOrigin: CGPoint
    let backgroundFrame: CGRect?
    if overlay.backgroundStyle != .none {
      textOrigin = CGPoint(
        x: contentOrigin.x + backgroundPaddingHorizontal,
        y: contentOrigin.y + backgroundPaddingVertical
      )
      backgroundFrame = contentFrame
    } else {
      textOrigin = contentOrigin
      backgroundFrame = nil
    }

    let textFrame = CGRect(origin: textOrigin, size: measured.textSize)
    return CanvasPlacement(
      anchorCenter: anchor,
      contentFrame: contentFrame,
      textFrame: textFrame,
      backgroundFrame: backgroundFrame
    )
  }

  static func draw(
    overlay: StoryTextOverlay,
    in context: CGContext,
    canvasSize: CGSize,
    pixelScale: CGFloat
  ) {
    let trimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let placement = placement(for: overlay, canvasSize: canvasSize)
    let fontSize = fontSize(canvasWidth: canvasSize.width, scale: overlay.scale)
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: overlay.textFill.uiColor,
      .paragraphStyle: paragraphStyle(for: overlay.alignment),
    ]
    let attributed = NSAttributedString(string: trimmed, attributes: attributes)

    context.saveGState()
    context.translateBy(x: placement.anchorCenter.x * pixelScale, y: placement.anchorCenter.y * pixelScale)
    context.rotate(by: overlay.rotationRadians)
    context.scaleBy(x: pixelScale, y: pixelScale)

    let localContent = CGRect(
      x: -placement.contentFrame.width / 2,
      y: -placement.contentFrame.height / 2,
      width: placement.contentFrame.width,
      height: placement.contentFrame.height
    )

    if let backgroundFrame = placement.backgroundFrame {
      let localBackground = CGRect(
        x: localContent.minX,
        y: localContent.minY,
        width: backgroundFrame.width,
        height: backgroundFrame.height
      )
      overlay.backgroundStyle.uiKitFill.setFill()
      UIBezierPath(roundedRect: localBackground, cornerRadius: backgroundCornerRadius).fill()
    }

    let localText = CGRect(
      x: localContent.minX + (placement.backgroundFrame == nil ? 0 : backgroundPaddingHorizontal),
      y: localContent.minY + (placement.backgroundFrame == nil ? 0 : backgroundPaddingVertical),
      width: placement.textFrame.width,
      height: placement.textFrame.height
    )
    attributed.draw(with: localText, options: [.usesLineFragmentOrigin], context: nil)
    context.restoreGState()
  }

  private static func paragraphStyle(for alignment: TextAlignment) -> NSMutableParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    switch alignment {
    case .leading: paragraph.alignment = .left
    case .center: paragraph.alignment = .center
    case .trailing: paragraph.alignment = .right
    }
    return paragraph
  }
}