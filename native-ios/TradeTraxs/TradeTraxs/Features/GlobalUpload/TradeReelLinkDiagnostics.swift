import Foundation

nonisolated enum TradeReelLinkDiagnostics {
    struct PostgrestPayload: Sendable {
        var code: String?
        var message: String?
        var details: String?
        var hint: String?
    }

    static func log(
        jobID: String,
        tradeID: String,
        reelID: String,
        stage: String,
        error: String? = nil
    ) {
        #if DEBUG
        var line =
            "[TRADE_REEL_LINK] jobID=\(jobID) tradeID=\(tradeID) reelID=\(reelID) stage=\(stage)"
        if let error, !error.isEmpty {
            line += " error=\(error)"
        }
        print(line)
        #endif
    }

    static func logResponse(
        jobID: String?,
        tradeID: String,
        reelID: String,
        httpStatus: Int,
        responseData: Data
    ) {
        #if DEBUG
        let parsed = parsePostgrest(responseData)
        let jobToken = jobID.map { "jobID=\($0) " } ?? ""
        print(
            """
            [TRADE_REEL_LINK_RESPONSE] \(jobToken)tradeID=\(tradeID) reelID=\(reelID) \
            httpStatus=\(httpStatus) \
            supabaseCode=\(parsed.code ?? "none") \
            supabaseMessage=\(parsed.message ?? "none") \
            supabaseDetails=\(parsed.details ?? "none") \
            supabaseHint=\(parsed.hint ?? "none") \
            responseBytes=\(responseData.count)
            """
        )
        #endif
    }

    static func parsePostgrest(_ data: Data) -> PostgrestPayload {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PostgrestPayload(
                code: nil,
                message: nil,
                details: nil,
                hint: nil
            )
        }
        return PostgrestPayload(
            code: object["code"] as? String,
            message: object["message"] as? String,
            details: object["details"] as? String,
            hint: object["hint"] as? String
        )
    }

    static func failureDetail(for error: Error) -> String {
        #if DEBUG
        return debugFailureMessage(for: error)
        #else
        return ProfileSectionSupport.message(for: error)
        #endif
    }

    #if DEBUG
    static func debugFailureMessage(for error: Error) -> String {
        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                switch network {
                case .validation(let statusCode, let message):
                    let codeText = statusCode.map { String($0) } ?? "none"
                    return "httpStatus=\(codeText) body=\(message)"
                case .server(let statusCode, let message):
                    return "httpStatus=\(statusCode) body=\(message ?? "none")"
                case .forbidden:
                    return "httpStatus=403 forbidden"
                case .unauthorized:
                    return "httpStatus=401 unauthorized"
                case .decoding(let message):
                    return "decodeFailure \(message)"
                default:
                    return String(describing: network)
                }
            case .unknown(let message):
                return message
            default:
                return String(describing: app)
            }
        }
        if let domain = error as? DomainError {
            return String(describing: domain)
        }
        return error.localizedDescription
    }
    #endif
}
