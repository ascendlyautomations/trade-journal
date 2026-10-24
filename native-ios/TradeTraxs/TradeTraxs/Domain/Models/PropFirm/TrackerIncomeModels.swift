import Foundation

nonisolated enum TrackerIncomeKind: String, CaseIterable, Hashable, Codable, Sendable {
    case withdrawal
    case business

    var title: String {
        switch self {
        case .withdrawal: return "Withdrawal"
        case .business: return "Business income"
        }
    }
}

nonisolated struct TrackerIncome: Identifiable, Hashable, Sendable {
    var id: String
    var incomeKind: TrackerIncomeKind
    var name: String
    var projectLabel: String?
    var amount: Decimal
    var dateReceived: String
    var paymentLabel: String?
    var notes: String?
    var recurrence: ExpenseRecurrence?
    var seriesID: String = ""
    var opensWithdrawal = false

    var savedID: String { seriesID.isEmpty ? id : seriesID }

    var subtitle: String {
        var parts = [incomeKind.title]
        if incomeKind == .business {
            let project = projectLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            parts.append(project.isEmpty ? "No project" : project)
        }
        if let recurrence { parts.append(recurrence.title) }
        parts.append(dateReceived)
        if let paymentLabel, !paymentLabel.isEmpty { parts.append(paymentLabel) }
        if opensWithdrawal { parts.append("From withdrawals") }
        return parts.joined(separator: " · ")
    }
}

nonisolated struct TrackerIncomeDraft: Hashable, Sendable {
    var incomeKind: TrackerIncomeKind = .business
    var name: String = ""
    var projectLabel: String = ""
    var amountDigits: String = ""
    var dateReceived: Date = .now
    var paymentLabel: String = ""
    var notes: String = ""
    var recurrence: ExpenseRecurrence?

    static func empty(now: Date = .now) -> TrackerIncomeDraft {
        TrackerIncomeDraft(dateReceived: now)
    }

    static func from(_ income: TrackerIncome) -> TrackerIncomeDraft {
        TrackerIncomeDraft(
            incomeKind: income.incomeKind,
            name: income.name,
            projectLabel: income.projectLabel ?? "",
            amountDigits: PropFirmExpenseMoney.editingText(income.amount),
            dateReceived: PropFirmExpenseMoney.date(fromDay: income.dateReceived) ?? .now,
            paymentLabel: income.paymentLabel ?? "",
            notes: income.notes ?? "",
            recurrence: income.recurrence
        )
    }

    static func validate(_ draft: TrackerIncomeDraft, today: String) -> String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return draft.incomeKind == .withdrawal ? "Enter where this withdrawal came from." : "Enter who paid you."
        }
        if name.count > 120 { return "Name is too long." }
        if draft.incomeKind == .business,
           draft.projectLabel.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return "Business or project label is too long."
        }
        guard PropFirmExpenseMoney.parse(draft.amountDigits) != nil else {
            return "Enter an amount greater than zero."
        }
        let day = PropFirmExpenseMoney.dayString(from: draft.dateReceived)
        if day > today { return "Date received cannot be in the future." }
        if draft.paymentLabel.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return "Bank or card label is too long."
        }
        if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).count > 500 {
            return "Notes are too long."
        }
        return nil
    }
}

nonisolated enum TrackerIncomeSchedule {
    static func expand(_ rows: [TrackerIncome], through: String) -> [TrackerIncome] {
        rows.flatMap { income in
            let days = ExpenseRecurrenceSchedule.dates(
                from: income.dateReceived,
                recurrence: income.recurrence,
                through: through
            )
            if days.count <= 1 {
                var row = income
                if row.seriesID.isEmpty { row.seriesID = income.id }
                return [row]
            }
            return days.map { day in
                var row = income
                row.seriesID = income.id
                row.id = "\(income.id):\(day)"
                row.dateReceived = day
                return row
            }
        }
    }
}
