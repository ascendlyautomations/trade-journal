import Foundation

#if DEBUG
/// DEBUG-only Trade Room message send tracing — no tokens or message bodies.
enum RoomMessageSendProbe {
    struct Context: Sendable {
        var roomID: String
        var channelID: String?
        var senderID: String?
        var messageType: String
        var hasReply: Bool
    }

    nonisolated static func logInsertAttempt(_ context: Context) {
        print(
            """
            [RoomMessageSend] attempt roomID=\(context.roomID) \
            channelID=\(context.channelID ?? "nil") \
            senderID=\(context.senderID ?? "nil") \
            type=\(context.messageType) hasReply=\(context.hasReply)
            """
        )
    }

    nonisolated static func logInsertSuccess(_ context: Context, messageID: String) {
        print(
            """
            [RoomMessageSend] success roomID=\(context.roomID) \
            channelID=\(context.channelID ?? "nil") \
            messageID=\(messageID)
            """
        )
    }

    nonisolated static func logFailed(_ context: Context, error: Error) {
        print("[RoomMessageSend] FAILED roomID=\(context.roomID) channelID=\(context.channelID ?? "nil")")
        print("[RoomMessageSend] errorType=\(String(reflecting: type(of: error)))")
        let postgrest = postgrestDetail(from: error)
        if let status = postgrest.httpStatus {
            print("[RoomMessageSend] httpStatus=\(status)")
        }
        if let code = postgrest.code {
            print("[RoomMessageSend] postgrestCode=\(code)")
        }
        if let message = postgrest.message {
            print("[RoomMessageSend] postgrestMessage=\(message)")
        }
        if let details = postgrest.details {
            print("[RoomMessageSend] postgrestDetails=\(details)")
        }
        if let hint = postgrest.hint {
            print("[RoomMessageSend] postgrestHint=\(hint)")
        }
    }

    nonisolated static func logReconciled(_ context: Context, messageID: String) {
        print(
            """
            [RoomMessageSend] reconciled-after-error roomID=\(context.roomID) \
            messageID=\(messageID)
            """
        )
    }

    nonisolated private static func postgrestDetail(from error: Error) -> PostgRESTValidationDetail {
        if let network = extractNetworkError(error) {
            switch network {
            case .server(let code, let message):
                return PostgRESTValidationDetail.parse(httpStatus: code, body: message ?? "")
            case .validation(let code, let message):
                return PostgRESTValidationDetail.parse(httpStatus: code, body: message)
            case .decoding(let message):
                return PostgRESTValidationDetail(
                    httpStatus: nil,
                    code: "decode",
                    message: message,
                    details: nil,
                    hint: nil
                )
            default:
                break
            }
        }
        return PostgRESTValidationDetail.parse(httpStatus: nil, body: String(describing: error))
    }

    nonisolated private static func extractNetworkError(_ error: Error) -> NetworkError? {
        if let network = error as? NetworkError { return network }
        if let app = error as? AppError, case .transport(let transport) = app {
            return transport
        }
        return nil
    }
}
#else
enum RoomMessageSendProbe {
    struct Context: Sendable {
        var roomID: String = ""
        var channelID: String?
        var senderID: String?
        var messageType: String = ""
        var hasReply: Bool = false
    }

    nonisolated static func logInsertAttempt(_ context: Context) {}
    nonisolated static func logInsertSuccess(_ context: Context, messageID: String) {}
    nonisolated static func logFailed(_ context: Context, error: Error) {}
    nonisolated static func logReconciled(_ context: Context, messageID: String) {}
}
#endif
