import SwiftUI

struct UnicodeEmojiCatalogEntry: Hashable, Codable, Sendable, Identifiable {
  var emoji: String
  var name: String
  var category: String

  var id: String { emoji }
}

/// Full Unicode emoji picker for message + livestream reactions.
struct UnicodeEmojiPickerSheet: View {
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.themeColors) private var colors
  @State private var query = ""

  private let catalog = UnicodeEmojiCatalog.shared
  private let columnCount = 7
  private let cellHeight: CGFloat = 44
  private let emojiPointSize: CGFloat = 30

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(minimum: 36, maximum: 52), spacing: 4), count: columnCount)
  }

  private var filtered: [UnicodeEmojiCatalogEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return catalog }
    let lower = needle.lowercased()
    return catalog.filter { entry in
      entry.name.localizedCaseInsensitiveContains(lower)
        || entry.category.localizedCaseInsensitiveContains(lower)
        || entry.emoji.contains(needle)
    }
  }

  private var groupedWhenBrowsing: [(category: String, rows: [UnicodeEmojiCatalogEntry])] {
    UnicodeEmojiCatalog.grouped(filtered)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md, pinnedViews: [.sectionHeaders]) {
          if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ForEach(groupedWhenBrowsing, id: \.category) { section in
              Section {
                emojiGrid(section.rows)
              } header: {
                categoryHeader(section.category)
              }
            }
          } else {
            emojiGrid(filtered)
          }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.sm)
      }
      .scrollDismissesKeyboard(.interactively)
      .searchable(text: $query, prompt: "Search emoji")
      .background(pickerBackground)
      .navigationTitle("Pick emoji")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private var pickerBackground: Color {
    colorScheme == .light ? colors.appBackground : colors.elevatedSurface
  }

  @ViewBuilder
  private func categoryHeader(_ title: String) -> some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(colors.secondaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, ExperienceSpacing.xs)
      .padding(.bottom, ExperienceSpacing.xxs)
      .background(pickerBackground.opacity(0.98))
  }

  @ViewBuilder
  private func emojiGrid(_ entries: [UnicodeEmojiCatalogEntry]) -> some View {
    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(entries) { entry in
        emojiCell(entry)
      }
    }
  }

  private func emojiCell(_ entry: UnicodeEmojiCatalogEntry) -> some View {
    Button {
      onSelect(entry.emoji)
      dismiss()
    } label: {
      Text(entry.emoji)
        .font(.system(size: emojiPointSize))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.experiencePlain)
    .accessibilityLabel(entry.name)
  }
}

/// Loads bundled Unicode emoji catalog (emoji grapheme + search metadata).
nonisolated enum UnicodeEmojiCatalog {
  static let categoryOrder: [String] = [
    "Smileys & Emotion",
    "People & Body",
    "Animals & Nature",
    "Food & Drink",
    "Travel & Places",
    "Activities",
    "Objects",
    "Symbols",
    "Flags",
    "Component",
    "Other",
  ]

  static let shared: [UnicodeEmojiCatalogEntry] = {
    let decoder = JSONDecoder()
    let candidates = [
      Bundle.main.url(forResource: "UnicodeEmojiCatalog", withExtension: "json"),
      Bundle.main.url(forResource: "UnicodeEmojiCatalog", withExtension: "json", subdirectory: "Resources"),
    ]

    for url in candidates.compactMap({ $0 }) {
      guard let data = try? Data(contentsOf: url) else { continue }

      if let structured = try? decoder.decode([UnicodeEmojiCatalogEntry].self, from: data),
         !structured.isEmpty
      {
        return structured
      }

      // Legacy flat strings: extract grapheme + name from emoji-test lines.
      if let legacy = try? decoder.decode([String].self, from: data), !legacy.isEmpty {
        let parsed = legacy.compactMap(parseLegacyLine)
        if !parsed.isEmpty { return parsed }
      }
    }

    return MessageReactionSemantics.quickPickEmojis.map {
      UnicodeEmojiCatalogEntry(emoji: $0, name: $0, category: "Smileys & Emotion")
    }
  }()

  static func grouped(_ entries: [UnicodeEmojiCatalogEntry]) -> [(category: String, rows: [UnicodeEmojiCatalogEntry])] {
    let buckets = Dictionary(grouping: entries, by: \.category)
    var ordered: [(String, [UnicodeEmojiCatalogEntry])] = []
    for title in categoryOrder {
      guard let rows = buckets[title], !rows.isEmpty else { continue }
      ordered.append((title, rows))
    }
    let extras = buckets.keys.filter { !categoryOrder.contains($0) }.sorted()
    for title in extras {
      guard let rows = buckets[title], !rows.isEmpty else { continue }
      ordered.append((title, rows))
    }
    return ordered
  }

  private static func parseLegacyLine(_ line: String) -> UnicodeEmojiCatalogEntry? {
    guard let hashRange = line.range(of: "#") else { return nil }
    let rest = String(line[hashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard let match = rest.range(of: #"\s+E\d+(?:\.\d+)?\s+"#, options: .regularExpression) else {
      return nil
    }
    let emoji = String(rest[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
    let name = String(rest[match.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard !emoji.isEmpty, !name.isEmpty else { return nil }
    return UnicodeEmojiCatalogEntry(emoji: emoji, name: name, category: "Other")
  }
}