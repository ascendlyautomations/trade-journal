import Foundation

#if DEBUG
enum NetworkCancelDiagnostics {
    static func log(requestPath: String, reason: String, cancelSource: String?) {
        print(
            """
            [NETWORK_CANCEL] request=\(requestPath) reason=\(reason) \
            taskCancelled=\(Task.isCancelled) cancelSource=\(cancelSource ?? "cooperativeTaskCheck")
            """
        )
    }
}
#else
enum NetworkCancelDiagnostics {
    static func log(requestPath: String, reason: String, cancelSource: String?) {}
}
#endif
