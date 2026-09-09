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

    nonisolated static func loadStarted(roomID: RoomID) {
        print("[RoomMembers] loadStarted roomID=\(roomID.rawValue)")
    }

    nonisolated static func membershipsReturned(count: Int, httpStatus: Int? = nil) {
        if let httpStatus {
            print("[RoomMembers] membershipsReturned count=\(count) status=\(httpStatus)")
        } else {
            print("[RoomMembers] membershipsReturned count=\(count)")
        }
    }

    nonisolated static func profilesRequested(count: Int) {
        print("[RoomMembers] profilesRequested count=\(count)")
    }

    nonisolated static func profilesReturned(count: Int) {
        print("[RoomMembers] profilesReturned count=\(count)")
    }

    nonisolated static func decoded(count: Int) {
        print("[RoomMembers] decoded count=\(count)")
    }

    nonisolated static func uiVisibleCount(_ count: Int) {
        print("[RoomMembers] UIVisibleCount=\(count)")
    }

    nonisolated static func ensureDefaults(status: String) {
        print("[RoomMembers] ensureDefaults status=\(status)")
    }

    nonisolated static func tags(count: Int) {
        print("[RoomMembers] tags count=\(count)")
    }

    nonisolated static func assignments(count: Int) {
        print("[RoomMembers] assignments count=\(count)")
    }

    nonisolated static func failed(stage: Stage, operation: String, error: Error) {
        let detail = failureDetail(for: error)
        print(
            "[RoomMembers] failed stage=\(stage.rawValue) "
                + "status=\(detail.status) "
                + "errorType=\(detail.errorType) "
                + "message=\(detail.message) "
                + "operation=\(operation)"
        )
    }

    nonisolated static func tagEnrichmentFailed(operation: String, error: Error) {
        let detail = failureDetail(for: error)
        print(
            "[RoomMembers] tagEnrichmentFailed "
                + "status=\(detail.status) "
                + "errorType=\(detail.errorType) "
                + "message=\(detail.message) "
                + "operation=\(operation)"
        )
    }

    nonisolated private static func failureDetail(for error: Error) -> (status: String, errorType: String, message: String) {
        var status = "unknown"
        var message = PostgRESTValidationDetail.safeField(error.localizedDescription, max: 160)
        let errorType = String(describing: type(of: error))

        if let app = error as? AppError {
            switch app {
            case .transport(let network):
                let parts = networkErrorParts(network)
                status = parts.status
                message = parts.message
            case .unknown(let text):
                let parsed = PostgRESTValidationDetail.parse(httpStatus: nil, body: text)
                status = parsed.httpStatus.map(String.init) ?? "unknown"
                message = parsed.message ?? PostgRESTValidationDetail.safeField(text, max: 160)
            case .cancelled:
                status = "cancelled"
                message = "cancelled"
            case .authentication:
                status = "401"
            case .notImplemented(let feature):
                message = "notImplemented:\(feature)"
            }
        } else if let network = error as? NetworkError {
            let parts = networkErrorParts(network)
            status = parts.status
            message = parts.message
        }

        return (status, errorType, message)
    }

    nonisolated private static func networkErrorParts(_ error: NetworkError) -> (status: String, message: String) {
        switch error {
        case .decoding(let text):
            return ("decode", PostgRESTValidationDetail.safeField(text, max: 160))
        case .validation(let statusCode, let text):
            let parsed = PostgRESTValidationDetail.parse(httpStatus: statusCode, body: text)
            return (
                String(parsed.httpStatus ?? statusCode ?? 0),
                parsed.message ?? PostgRESTValidationDetail.safeField(text, max: 160)
            )
        case .server(let statusCode, let text):
            return (
                String(statusCode),
                PostgRESTValidationDetail.safeField(text ?? "", max: 160)
            )
        case .unauthorized:
            return ("401", "unauthorized")
        case .forbidden:
            return ("403", "forbidden")
        case .connectivity:
            return ("offline", "connectivity")
        case .timeout:
            return ("timeout", "timeout")
        case .cancelled:
            return ("cancelled", "cancelled")
        case .rateLimited:
            return ("429", "rateLimited")
        case .unknown(let text):
            return ("unknown", PostgRESTValidationDetail.safeField(text, max: 160))
        }
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

    static func loadStarted(roomID: RoomID) {}
    static func membershipsReturned(count: Int, httpStatus: Int? = nil) {}
    static func profilesRequested(count: Int) {}
    static func profilesReturned(count: Int) {}
    static func decoded(count: Int) {}
    static func uiVisibleCount(_ count: Int) {}
    static func ensureDefaults(status: String) {}
    static func tags(count: Int) {}
    static func assignments(count: Int) {}
    static func failed(stage: Stage, operation: String, error: Error) {}
    static func tagEnrichmentFailed(operation: String, error: Error) {}

    // Legacy call sites during migration
    static func begin(roomID: RoomID) { loadStarted(roomID: roomID) }
    static func memberships(httpStatus: Int?, count: Int) { membershipsReturned(count: count, httpStatus: httpStatus) }
    static func profiles(count: Int) { profilesReturned(count: count) }
    static func completed(roomID: RoomID, memberCount: Int) { uiVisibleCount(memberCount) }
}
#endif
