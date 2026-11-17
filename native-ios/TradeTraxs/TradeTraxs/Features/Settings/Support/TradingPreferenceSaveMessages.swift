import Foundation

/// User-visible copy when Trading Rules save fails. Parses PostgREST / Postgres errors.
nonisolated enum TradingPreferenceSaveMessages {
    enum Phase: Sendable, Equatable {
        case globalRules
        case accountOverrides
    }

    static func loadMessage(for error: Error) -> String {
        let detail = parseDetail(from: error)
        let haystack = [detail.code, detail.message, detail.details]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("pgrst204")
            || haystack.contains("could not find")
            || (haystack.contains("column") && haystack.contains("schema cache"))
        {
            return """
            Could not load trading rules: the server database is missing the latest Trading Rules columns. \
            Apply migration 20261112210000_trading_rules_expansion, then try again.
            """
        }
        if let network = networkMessage(error) {
            return "Could not load trading rules. \(network)"
        }
        return "Could not load trading rules. Check your connection and try again."
    }

    static func message(
        for error: Error,
        phase: Phase,
        accountLabel: String? = nil
    ) -> String {
        let detail = parseDetail(from: error)
        if let tailored = tailoredMessage(detail: detail, phase: phase, accountLabel: accountLabel) {
            return tailored
        }
        if let network = networkMessage(error) {
            return network
        }
        if let app = error as? AppError, case .unknown(let text) = app {
            if text == "Failed to decode Supabase response"
                || text == "Upsert returned empty representation"
            {
                return """
                The server saved your changes, but the app could not read the confirmation. \
                Pull to refresh or reopen this screen to verify.
                """
            }
        }
        if error is DecodingError {
            return """
            The server may have saved your changes, but the response could not be read. \
            Reopen Trading Rules to confirm, or try again.
            """
        }
        switch phase {
        case .globalRules:
            return "Could not save trading rules. Check your connection and try again."
        case .accountOverrides:
            return "Global rules were saved, but account overrides could not be saved. Try again."
        }
    }

    private static func parseDetail(from error: Error) -> PostgRESTValidationDetail {
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                return parseDetail(from: network)
            case .unknown(let message):
                return PostgRESTValidationDetail.parse(httpStatus: nil, body: message)
            default:
                break
            }
        }
        if let network = error as? NetworkError {
            return parseDetail(from: network)
        }
        return PostgRESTValidationDetail.parse(httpStatus: nil, body: String(describing: error))
    }

    private static func parseDetail(from network: NetworkError) -> PostgRESTValidationDetail {
        switch network {
        case .validation(let status, let message):
            return PostgRESTValidationDetail.parse(httpStatus: status, body: message)
        case .server(let status, let message):
            return PostgRESTValidationDetail.parse(httpStatus: status, body: message ?? "")
        case .unknown(let message):
            return PostgRESTValidationDetail.parse(httpStatus: nil, body: message)
        default:
            return PostgRESTValidationDetail(httpStatus: nil, code: nil, message: nil, details: nil, hint: nil)
        }
    }

    private static func tailoredMessage(
        detail: PostgRESTValidationDetail,
        phase: Phase,
        accountLabel: String?
    ) -> String? {
        let haystack = [
            detail.code,
            detail.message,
            detail.details,
            detail.hint,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if haystack.contains("pgrst204")
            || haystack.contains("could not find")
            || (haystack.contains("column") && haystack.contains("schema cache"))
        {
            return """
            The server database is missing the latest Trading Rules columns. \
            Apply migration 20261112210000_trading_rules_expansion (and earlier trading preference migrations), \
            then try again.
            """
        }

        if haystack.contains("trading_preferences_profit_stop_requires_target")
            || (haystack.contains("profit_stop") && haystack.contains("daily_profit_target"))
        {
            return "Set a daily profit target before turning on stop-after-target."
        }

        if haystack.contains("trading_preferences_sessions_check") {
            return "One or more preferred sessions are not allowed. Pick from the listed sessions only."
        }

        if haystack.contains("trading_preference_symbols_ok")
            || haystack.contains("trading_preferences_instruments_check")
        {
            return "Use 1–16 letters, numbers, or . / - for each primary instrument (up to 12)."
        }

        if haystack.contains("trading_preferences_hours_check")
            || haystack.contains("planned_start_minute")
            || haystack.contains("planned_end_minute")
        {
            return "Enter both an Eastern start and end time, and make them different."
        }

        if haystack.contains("account does not belong") {
            return "That account override is not valid for your profile. Choose an account you own."
        }

        if haystack.contains("23514") || haystack.contains("check constraint") {
            if phase == .accountOverrides {
                return "Account override values did not pass server checks. Use amounts above 0 or leave fields blank."
            }
            return "One or more rule values did not pass server checks. Review amounts, sessions, and instruments."
        }

        if let message = detail.message, !message.isEmpty, !message.hasPrefix("{") {
            let cleaned = PostgRESTValidationDetail.safeField(message, max: 180)
            if cleaned != "empty", !cleaned.lowercased().contains("jwt") {
                switch phase {
                case .globalRules:
                    return "Could not save trading rules: \(cleaned)"
                case .accountOverrides:
                    if let accountLabel, !accountLabel.isEmpty {
                        return "Could not save overrides for \(accountLabel): \(cleaned)"
                    }
                    return "Could not save account overrides: \(cleaned)"
                }
            }
        }

        return nil
    }

    private static func networkMessage(_ error: Error) -> String? {
        if let app = error as? AppError, case .transport(let network) = app {
            return UserFacingError.map(network).message
        }
        if let network = error as? NetworkError {
            let mapped = UserFacingError.map(network).message
            if mapped != "Please try again." {
                return mapped
            }
        }
        return nil
    }
}
