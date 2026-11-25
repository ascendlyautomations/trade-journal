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

    private static let slicePalette: [Color] = [
        Color(red: 0.11, green: 0.74, blue: 0.69),
        Color(red: 0.22, green: 0.78, blue: 0.44),
        Color(red: 0.97, green: 0.55, blue: 0.18),
        Color(red: 0.58, green: 0.40, blue: 0.93),
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.93, green: 0.36, blue: 0.62),
        Color(red: 0.40, green: 0.78, blue: 0.82),
        Color(red: 0.86, green: 0.64, blue: 0.22),
    ]

    static func sliceColor(for label: String) -> Color {
        slicePalette[stablePaletteIndex(for: label)]
    }

    private static func stablePaletteIndex(for label: String) -> Int {
        var hasher = Hasher()
        hasher.combine(label.lowercased())
        return abs(hasher.finalize()) % slicePalette.count
    }
}

/// Popover copy for Expense Tracker section headers (ⓘ).
nonisolated enum PropFirmExpenseTrackerSectionInfo {
    static let spendingBreakdown =
        "See how your recorded expenses are distributed across categories and where you're spending the most."

    static let spendingAnalytics =
        "Explore your spending trends over time, including changes in expenses and category performance."

    static let taxDeductible =
        """
        View expenses that may qualify as tax deductions. Eligibility depends on your business activity and applicable tax rules. These amounts are estimates, not confirmed deductions.

        The estimated total is a bookkeeping figure from recorded prop firm expenses. Consult a tax professional before claiming deductions. Not every recorded expense is guaranteed to qualify as a tax deduction.
        """

    static let taxReserve =
        "Set aside a percentage of your recorded income to help prepare for potential taxes. This is a budgeting estimate, not a calculation of your actual tax liability."

    static let exportTaxCSV =
        """
        Export your recorded expenses and supported payout information into a CSV file for bookkeeping or review with your tax professional. Exported expenses are not automatically tax-deductible.
        """
}