import Foundation

/// Display-only dedup when a clip caption repeats linked trade journal / public text.
enum LinkedContentCaptionDedup {
  nonisolated static func normalizedForComparison(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
    return parts.joined(separator: " ")
  }

  nonisolated static func areEquivalent(_ a: String?, _ b: String?) -> Bool {
    guard let left = normalizedForComparison(a),
          let right = normalizedForComparison(b)
    else { return false }
    return left == right
  }

  /// Candidate trade text fields that may repeat the clip caption (notes, public caption, preview).
  nonisolated static func tradeTextFields(for trade: Trade) -> [String] {
    [trade.publicCaption, trade.notes, trade.notePreview]
      .compactMap { normalizedForComparison($0) }
  }

  /// Hide linked-trade description when it duplicates the clip caption already shown above.
  nonisolated static func shouldHideTradeDescription(
    displayedClipCaption: String?,
    tradeDescription: String?
  ) -> Bool {
    areEquivalent(displayedClipCaption, tradeDescription)
  }
}
