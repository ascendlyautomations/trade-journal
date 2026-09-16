import Foundation
import OSLog

#if DEBUG
/// DEBUG-only guest Feed RPC diagnostics (no secrets).
enum ExploreGuestFeedDiagnostics {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "ExploreGuestFeed")

    static func logSuccess(rpc: String) {
        emit(
            rpc: rpc,
            httpStatus: 200,
            postgrestCode: nil,
            message: nil,
            details: nil,
            hint: nil
        )
    }

    static func logFailure(rpc: String, error: Error) {
        let parsed = parse(error: error)
        emit(
            rpc: rpc,
            httpStatus: parsed.httpStatus,
            postgrestCode: parsed.code,
            message: parsed.message,
            details: parsed.details,
            hint: parsed.hint
        )
    }

    private static func emit(
        rpc: String,
        httpStatus: Int?,
        postgrestCode: String?,
        message: String?,
        details: String?,
        hint: String?
    ) {
        let config = AppConfiguration.make(for: .current)
        let hasAnon = config.isSupabaseConfigured
        let line = """
        [ExploreGuestFeed] rpc=\(rpc) httpStatus=\(httpStatus.map(String.init) ?? "nil") \
        postgrestCode=\(postgrestCode ?? "nil") message=\(message ?? "nil") \
        details=\(details ?? "nil") hint=\(hint ?? "nil") \
        hasAnonAPIKey=\(hasAnon) hasBearerAnonToken=\(hasAnon) hasUserSession=false
        """
        log.info("\(line, privacy: .public)")
    }

    private static func parse(error: Error) -> PostgRESTValidationDetail {
        if let rpc = error as? BackendV2RPCError {
            switch rpc {
            case .requestValidation(let detail):
                return detail
            case .transport(let message):
                return PostgRESTValidationDetail(
                    httpStatus: nil,
                    code: nil,
                    message: PostgRESTValidationDetail.safeField(message, max: 96),
                    details: nil,
                    hint: nil
                )
            default:
                break
            }
        }
        if case AppError.authentication(let reason) = error {
            return PostgRESTValidationDetail(
                httpStatus: nil,
                code: "client.auth",
                message: String(describing: reason),
                details: nil,
                hint: nil
            )
        }
        if case AppError.transport(let network) = error,
           case .validation(let status, let body) = network
        {
            return PostgRESTValidationDetail.parse(httpStatus: status, body: body)
        }
        if case NetworkError.validation(let status, let body) = error {
            return PostgRESTValidationDetail.parse(httpStatus: status, body: body)
        }
        if case NetworkError.unauthorized = error {
            return PostgRESTValidationDetail(httpStatus: 401, code: "401", message: "unauthorized", details: nil, hint: nil)
        }
        if case NetworkError.forbidden = error {
            return PostgRESTValidationDetail(httpStatus: 403, code: "403", message: "forbidden", details: nil, hint: nil)
        }
        return PostgRESTValidationDetail(
            httpStatus: nil,
            code: nil,
            message: PostgRESTValidationDetail.safeField(String(describing: error), max: 96),
            details: nil,
            hint: nil
        )
    }
}
#endif
