import Foundation

#if DEBUG
nonisolated enum NetworkCancelDiagnostics {
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
nonisolated enum NetworkCancelDiagnostics {
    static func log(requestPath: String, reason: String, cancelSource: String?) {}
}
#endif
