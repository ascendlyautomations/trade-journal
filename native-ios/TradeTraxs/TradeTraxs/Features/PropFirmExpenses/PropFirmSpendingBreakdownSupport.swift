import SwiftUI

enum PropFirmSpendingBreakdownMode: String, CaseIterable, Identifiable {
    case type
    case category
    case business
    case project

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: return "Type"
        case .category: return "Category"
        case .business: return "Business"
        case .project: return "Project"
        }
    }
}

enum PropFirmSpendingBreakdownSupport {
    static func rows(
        mode: PropFirmSpendingBreakdownMode,
        expenses: [PropFirmExpense]
    ) -> [PropFirmExpenseBreakdown] {
        switch mode {
        case .type:
            return grouped(expenses, label: { $0.trackerKind.title })
        case .category:
            return grouped(expenses, label: { $0.categoryTitle })
        case .business:
            let business = expenses.filter { $0.trackerKind == .business }
            return grouped(business, label: { expense in
                let label = expense.projectLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return label.isEmpty ? "Unassigned" : label
            })
        case .project:
            return grouped(expenses, label: { $0.projectTitle })
        }
    }

    private static func grouped(
        _ rows: [PropFirmExpense],
        label: (PropFirmExpense) -> String
    ) -> [PropFirmExpenseBreakdown] {
        var buckets: [String: (String, Decimal)] = [:]
        for expense in rows {
            let name = label(expense)
            let key = name.lowercased()
            var row = buckets[key] ?? (name, .zero)
            row.1 += expense.totalCost
            buckets[key] = row
        }
        return buckets.values
            .map { PropFirmExpenseBreakdown(id: $0.0, label: $0.0, total: $0.1) }
            .sorted { $0.total == $1.total ? $0.label < $1.label : $0.total > $1.total }
    }

    static func sliceColor(index: Int, colors: SemanticColorPalette) -> Color {
        let palette: [Color] = [
            colors.accent,
            colors.profit,
            colors.info,
            colors.loss.opacity(0.85),
            colors.secondaryText.opacity(0.75),
            colors.accent.opacity(0.65),
        ]
        return palette[index % palette.count]
    }
}