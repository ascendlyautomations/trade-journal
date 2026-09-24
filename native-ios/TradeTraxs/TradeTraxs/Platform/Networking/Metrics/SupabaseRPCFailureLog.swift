import Foundation
import OSLog

/// Sanitized PostgREST / RPC failure diagnostics (no tokens).
nonisolated enum SupabaseRPCFailureLog {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "SupabaseRPC"
    )

    static func logHTTPFailure(
        path: String,
        method: String,
        statusCode: Int,
        body: Data?,
        requestID: UUID?,
        elapsedMs: Double?
    ) {
        guard path.contains("/rest/v1/rpc/") else { return }
        let rpcName = path.split(separator: "/").last.map(String.init) ?? path
        let bodyText = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let detail = PostgRESTValidationDetail.parse(httpStatus: statusCode, body: bodyText)
        let req = requestID.map { $0.uuidString.prefix(8) } ?? "n/a"
        let elapsed = elapsedMs.map { String(format: "%.1f", $0) } ?? "n/a"
        logger.error(
            """
            rpcFailure rpc=\(rpcName, privacy: .public) \
            method=\(method, privacy: .public) \
            status=\(statusCode, privacy: .public) \
            \(detail.telemetrySummary, privacy: .public) \
            requestID=\(req, privacy: .public) \
            elapsedMs=\(elapsed, privacy: .public)
            """
        )
    }
}
