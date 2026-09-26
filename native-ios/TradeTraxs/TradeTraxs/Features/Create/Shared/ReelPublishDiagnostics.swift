import Foundation

#if DEBUG
enum ReelPublishDiagnostics {
    static func logTapReceived(selectionID: String? = nil) {
        if let selectionID {
            print("[ReelPublish] tapReceived selectionID=\(selectionID)")
        } else {
            print("[ReelPublish] tapReceived")
        }
    }

    static func logUsingPreparedVideo(selectionID: String, exists: Bool) {
        print("[ReelPublish] usingPreparedVideo selectionID=\(selectionID) exists=\(exists)")
    }

    static func logAccepted(publishID: String, selectionID: String? = nil) {
        if let selectionID {
            print("[ReelPublish] accepted publishID=\(publishID) selectionID=\(selectionID)")
        } else {
            print("[ReelPublish] accepted publishID=\(publishID)")
        }
    }

    static func logDuplicateInvocationIgnored(publishID: String) {
        print("[ReelPublish] duplicateInvocationIgnored publishID=\(publishID)")
    }

    static func logRejected(reason: String) {
        print("[ReelPublish] rejected reason=\(reason)")
    }

    static func logValidationStarted(publishID: String) {
        print("[ReelPublish] validationStarted publishID=\(publishID)")
    }

    static func logValidationCompleted(publishID: String) {
        print("[ReelPublish] validationCompleted publishID=\(publishID)")
    }

    static func logPreparationStarted(publishID: String) {
        print("[ReelPublish] preparationStarted publishID=\(publishID)")
    }

    static func logPreparationCompleted(
        publishID: String,
        byteCount: Int,
        durationSeconds: Int
    ) {
        print(
            """
            [ReelPublish] preparationCompleted publishID=\(publishID) \
            byteCount=\(byteCount) durationSeconds=\(durationSeconds)
            """
        )
    }

    static func logUploadAssetResolved(publishID: String, byteCount: Int, assetState: String) {
        print(
            """
            [ReelPublish] uploadAssetResolved publishID=\(publishID) \
            bytes=\(byteCount) assetState=\(assetState)
            """
        )
    }

    static func logPreflightStarted(publishID: String, tradeID: String?) {
        if let tradeID {
            print("[ReelPublish] preflightStarted publishID=\(publishID) tradeID=\(tradeID)")
        } else {
            print("[ReelPublish] preflightStarted publishID=\(publishID) tradeID=none")
        }
    }

    static func logPreflightCompleted(publishID: String) {
        print("[ReelPublish] preflightCompleted publishID=\(publishID)")
    }

    static func logVideoUploadStarted(publishID: String, objectIdentity: String, byteCount: Int) {
        print(
            """
            [ReelPublish] videoUploadStarted publishID=\(publishID) \
            objectIdentity=\(objectIdentity) byteCount=\(byteCount)
            """
        )
    }

    static func logVideoUploadCompleted(publishID: String, statusCode: Int) {
        print(
            """
            [ReelPublish] videoUploadCompleted publishID=\(publishID) \
            status=\(statusCode)
            """
        )
    }

    static func logThumbnailUploadStarted(publishID: String, objectIdentity: String) {
        print(
            """
            [ReelPublish] thumbnailUploadStarted publishID=\(publishID) \
            objectIdentity=\(objectIdentity)
            """
        )
    }

    static func logThumbnailUploadCompleted(publishID: String, statusCode: Int) {
        print(
            """
            [ReelPublish] thumbnailUploadCompleted publishID=\(publishID) \
            status=\(statusCode)
            """
        )
    }

    static func logDatabaseInsertStarted(publishID: String) {
        print("[ReelPublish] databaseInsertStarted publishID=\(publishID)")
    }

    static func logDatabaseInsertCompleted(publishID: String, reelID: String) {
        print(
            """
            [ReelPublish] databaseInsertCompleted publishID=\(publishID) \
            reelID=\(reelID)
            """
        )
    }

    static func logCacheRefreshStarted(publishID: String) {
        print("[ReelPublish] cacheRefreshStarted publishID=\(publishID)")
    }

    static func logCompleted(publishID: String) {
        print("[ReelPublish] completed publishID=\(publishID)")
    }

    static func logFailed(
        publishID: String,
        stage: String,
        error: Error
    ) {
        let details = failureDetails(for: error)
        print(
            """
            [ReelPublish] failed publishID=\(publishID) \
            stage=\(stage) \
            errorType=\(details.errorType) \
            statusCode=\(details.statusCode.map(String.init) ?? "none") \
            supabaseCode=\(details.supabaseCode ?? "none") \
            message=\(details.message)
            """
        )
    }

    // Legacy aliases used by pipeline internals during migration.
    static func logStarted(publishID: String) {
        logPreparationStarted(publishID: publishID)
    }

    static func logPrepareCompleted(publishID: String, byteCount: Int, durationSeconds: Int) {
        logPreparationCompleted(
            publishID: publishID,
            byteCount: byteCount,
            durationSeconds: durationSeconds
        )
    }

    static func logUploadStarted(publishID: String, objectIdentity: String, byteCount: Int) {
        logVideoUploadStarted(
            publishID: publishID,
            objectIdentity: objectIdentity,
            byteCount: byteCount
        )
    }

    static func logUploadResponse(publishID: String, objectIdentity: String, statusCode: Int) {
        logVideoUploadCompleted(publishID: publishID, statusCode: statusCode)
    }

    private struct FailureDetails {
        var errorType: String
        var statusCode: Int?
        var supabaseCode: String?
        var message: String
    }

    private static func failureDetails(for error: Error) -> FailureDetails {
        if let app = error as? AppError {
            switch app {
            case .cancelled:
                return FailureDetails(
                    errorType: "cancelled",
                    statusCode: nil,
                    supabaseCode: nil,
                    message: "Publish cancelled"
                )
            case .transport(let network):
                switch network {
                case .server(let code, let message):
                    return FailureDetails(
                        errorType: "transportServer",
                        statusCode: code,
                        supabaseCode: nil,
                        message: sanitized(message ?? "Server error")
                    )
                case .unauthorized:
                    return FailureDetails(
                        errorType: "transportUnauthorized",
                        statusCode: 401,
                        supabaseCode: nil,
                        message: "Unauthorized"
                    )
                case .forbidden:
                    return FailureDetails(
                        errorType: "transportForbidden",
                        statusCode: 403,
                        supabaseCode: nil,
                        message: "Forbidden"
                    )
                default:
                    return FailureDetails(
                        errorType: "transport",
                        statusCode: nil,
                        supabaseCode: nil,
                        message: sanitized(String(describing: network))
                    )
                }
            case .authentication(let auth):
                return FailureDetails(
                    errorType: "authentication",
                    statusCode: nil,
                    supabaseCode: nil,
                    message: sanitized(String(describing: auth))
                )
            case .unknown(let message):
                return FailureDetails(
                    errorType: "unknown",
                    statusCode: nil,
                    supabaseCode: nil,
                    message: sanitized(message)
                )
            case .notImplemented(let feature):
                return FailureDetails(
                    errorType: "notImplemented",
                    statusCode: nil,
                    supabaseCode: nil,
                    message: sanitized(feature)
                )
            }
        }
        if let domain = error as? DomainError {
            return FailureDetails(
                errorType: "domain",
                statusCode: nil,
                supabaseCode: nil,
                message: sanitized(String(describing: domain))
            )
        }
        return FailureDetails(
            errorType: String(describing: type(of: error)),
            statusCode: nil,
            supabaseCode: nil,
            message: sanitized(error.localizedDescription)
        )
    }

    private static func sanitized(_ message: String) -> String {
        message
            .replacingOccurrences(
                of: #"https?://[^\s]+"#,
                with: "<url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+"#,
                with: "<token>",
                options: .regularExpression
            )
    }
}
#else
enum ReelPublishDiagnostics {
    static func logTapReceived(selectionID: String? = nil) {}
    static func logUsingPreparedVideo(selectionID: String, exists: Bool) {}
    static func logAccepted(publishID: String, selectionID: String? = nil) {}
    static func logDuplicateInvocationIgnored(publishID: String) {}
    static func logRejected(reason: String) {}
    static func logValidationStarted(publishID: String) {}
    static func logValidationCompleted(publishID: String) {}
    static func logPreparationStarted(publishID: String) {}
    static func logPreparationCompleted(publishID: String, byteCount: Int, durationSeconds: Int) {}
    static func logUploadAssetResolved(publishID: String, byteCount: Int, assetState: String) {}
    static func logPreflightStarted(publishID: String, tradeID: String?) {}
    static func logPreflightCompleted(publishID: String) {}
    static func logVideoUploadStarted(publishID: String, objectIdentity: String, byteCount: Int) {}
    static func logVideoUploadCompleted(publishID: String, statusCode: Int) {}
    static func logThumbnailUploadStarted(publishID: String, objectIdentity: String) {}
    static func logThumbnailUploadCompleted(publishID: String, statusCode: Int) {}
    static func logDatabaseInsertStarted(publishID: String) {}
    static func logDatabaseInsertCompleted(publishID: String, reelID: String) {}
    static func logCacheRefreshStarted(publishID: String) {}
    static func logCompleted(publishID: String) {}
    static func logFailed(publishID: String, stage: String, error: Error) {}
    static func logStarted(publishID: String) {}
    static func logPrepareCompleted(publishID: String, byteCount: Int, durationSeconds: Int) {}
    static func logUploadStarted(publishID: String, objectIdentity: String, byteCount: Int) {}
    static func logUploadResponse(publishID: String, objectIdentity: String, statusCode: Int) {}
}
#endif
