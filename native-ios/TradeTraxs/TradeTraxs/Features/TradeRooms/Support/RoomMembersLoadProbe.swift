import Foundation

#if DEBUG
enum RoomMembersLoadProbe {
    enum Stage: String {
        case room
        case memberships
        case profiles
        case ensureDefaults
        case tags
        case assignments
        case tagEnrichment
        case memberCount
    }

    nonisolated static func begin(roomID: RoomID) {
        print("[RoomMembersLoad] begin roomId=\(roomID.rawValue)")
    }

    nonisolated static func memberships(httpStatus: Int?, count: Int) {
        let statusLabel = httpStatus.map { String($0) } ?? "unknown"
        print("[RoomMembersLoad] memberships status=\(statusLabel) count=\(count)")
    }

    nonisolated static func profiles(count: Int) {
        print("[RoomMembersLoad] profiles count=\(count)")
    }

    nonisolated static func ensureDefaults(status: String) {
        print("[RoomMembersLoad] ensureDefaults status=\(status)")
    }

    nonisolated static func tags(count: Int) {
        print("[RoomMembersLoad] tags count=\(count)")
    }

    nonisolated static func assignments(count: Int) {
        print("[RoomMembersLoad] assignments count=\(count)")
    }

    nonisolated static func completed(roomID: RoomID, memberCount: Int) {
        print("[RoomMembersLoad] completed roomId=\(roomID.rawValue) memberCount=\(memberCount)")
    }

    nonisolated static func failed(stage: Stage, operation: String, error: Error) {
        print(
            "[RoomMembersLoad] FAILED stage=\(stage.rawValue) "
                + "operation=\(operation) "
                + errorDetail(error)
        )
    }

    nonisolated static func tagEnrichmentFailed(operation: String, error: Error) {
        print(
            "[RoomMembersLoad] tagEnrichmentFailed operation=\(operation) "
                + errorDetail(error)
        )
    }

    nonisolated private static func errorDetail(_ error: Error) -> String {
        var parts: [String] = ["error=\(type(of: error))"]

        if let app = error as? AppError {
            parts.append(contentsOf: appErrorParts(app))
        } else if let network = error as? NetworkError {
            parts.append(contentsOf: networkErrorParts(network))
        } else {
            parts.append("message=\(PostgRESTValidationDetail.safeField(error.localizedDescription, max: 160))")
        }

        return parts.joined(separator: " ")
    }

    nonisolated private static func appErrorParts(_ error: AppError) -> [String] {
        switch error {
        case .transport(let network):
            return networkErrorParts(network)
        case .unknown(let message):
            return postgrestParts(httpStatus: nil, body: message)
        case .cancelled:
            return ["kind=cancelled"]
        case .authentication(let auth):
            return ["kind=authentication message=\(PostgRESTValidationDetail.safeField(String(describing: auth), max: 96))"]
        case .notImplemented(let feature):
            return ["kind=notImplemented feature=\(feature)"]
        }
    }

    nonisolated private static func networkErrorParts(_ error: NetworkError) -> [String] {
        switch error {
        case .decoding(let message):
            return ["kind=decoding message=\(PostgRESTValidationDetail.safeField(message, max: 160))"]
        case .validation(let statusCode, let message):
            return postgrestParts(httpStatus: statusCode, body: message)
        case .server(let statusCode, let message):
            return postgrestParts(httpStatus: statusCode, body: message ?? "")
        case .unauthorized:
            return ["httpStatus=401"]
        case .forbidden:
            return ["httpStatus=403"]
        case .connectivity:
            return ["kind=connectivity"]
        case .timeout:
            return ["kind=timeout"]
        case .cancelled:
            return ["kind=cancelled"]
        case .rateLimited(let retryAfter):
            let retryLabel = retryAfter.map { String($0) } ?? "nil"
            return ["kind=rateLimited retryAfter=\(retryLabel)"]
        case .unknown(let message):
            return ["kind=unknown message=\(PostgRESTValidationDetail.safeField(message, max: 160))"]
        }
    }

    nonisolated private static func postgrestParts(httpStatus: Int?, body: String) -> [String] {
        let parsed = PostgRESTValidationDetail.parse(httpStatus: httpStatus, body: body)
        var parts: [String] = []
        if let httpStatus = parsed.httpStatus ?? httpStatus {
            parts.append("httpStatus=\(httpStatus)")
        }
        if let code = parsed.code { parts.append("code=\(PostgRESTValidationDetail.safeField(code, max: 48))") }
        if let message = parsed.message {
            parts.append("message=\(PostgRESTValidationDetail.safeField(message, max: 96))")
        }
        if let details = parsed.details {
            parts.append("details=\(PostgRESTValidationDetail.safeField(details, max: 64))")
        }
        if let hint = parsed.hint { parts.append("hint=\(PostgRESTValidationDetail.safeField(hint, max: 64))") }
        if parts.isEmpty {
            parts.append("message=\(PostgRESTValidationDetail.safeField(body, max: 96))")
        }
        return parts
    }
}
#else
enum RoomMembersLoadProbe {
    enum Stage: String {
        case room
        case memberships
        case profiles
        case ensureDefaults
        case tags
        case assignments
        case tagEnrichment
        case memberCount
    }

    static func begin(roomID: RoomID) {}
    static func memberships(httpStatus: Int?, count: Int) {}
    static func profiles(count: Int) {}
    static func ensureDefaults(status: String) {}
    static func tags(count: Int) {}
    static func assignments(count: Int) {}
    static func completed(roomID: RoomID, memberCount: Int) {}
    static func failed(stage: Stage, operation: String, error: Error) {}
    static func tagEnrichmentFailed(operation: String, error: Error) {}
}
#endif
