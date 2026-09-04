import Foundation
import Observation

@Observable
@MainActor
final class DailyCheckInViewModel {
    var draft: TraderDailyCheckInDraft
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    var sleepHoursText: String {
        get {
            guard let hours = draft.sleepHours else { return "" }
            let number = NSDecimalNumber(decimal: hours)
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return number.stringValue
            }
            return String(format: "%.1f", number.doubleValue)
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                draft.sleepHours = nil
                return
            }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            if let value = Double(normalized) {
                draft.sleepHours = Decimal(value)
            }
        }
    }

    private let repository: any TraderDailyCheckInRepository
    private let session: any SessionProviding
    private let store: TraderDailyCheckInStore

    init(
        repository: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        store: TraderDailyCheckInStore? = nil,
        existing: TraderDailyCheckIn?,
        dateKey: String? = nil
    ) {
        self.repository = repository
        self.session = session
        self.store = store ?? TraderDailyCheckInStore.shared
        let resolvedDateKey = dateKey ?? existing?.checkInDate ?? self.store.todayDateKey
        if let existing {
            draft = TraderDailyCheckInDraft(checkIn: existing)
        } else {
            draft = .empty(for: resolvedDateKey)
        }
    }

    func save() async -> Bool {
        errorMessage = nil
        if let message = TraderDailyCheckInValidation.validate(draft) {
            errorMessage = message
            return false
        }
        guard let userID = await session.currentUserID else {
            errorMessage = "Sign in to save your check-in."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let saved = try await repository.upsert(
                draft,
                for: ProfileID(userID.rawValue)
            )
            if saved.checkInDate == store.todayDateKey {
                store.applySaved(saved)
            }
            SessionDailyCheckInsStore.shared.upsert(saved)
            CheckInHistorySessionStore.shared.refreshCheckIn(saved)
            return true
        } catch {
            errorMessage = UserFacingError.map(
                error as? AppError ?? AppError.unknown(message: error.localizedDescription)
            ).message
            return false
        }
    }
}
