import Foundation
import OSLog

#if DEBUG
nonisolated enum BrokerOAuthDebugLog {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "BrokerOAuth")

    static func tap() {
        log.info("[BrokerOAuth] tap")
    }

    static func authorizeRequest(client: String, bodyIncluded: Bool) {
        log.info("[BrokerOAuth] authorize.client=\(client, privacy: .public)")
        log.info("[BrokerOAuth] authorize.bodyIncluded=\(bodyIncluded, privacy: .public)")
    }

    static func authorizeResponse(status: Int, ok: Bool, hasAuthorizeURL: Bool) {
        log.info("[BrokerOAuth] authorize.response status=\(status, privacy: .public) ok=\(ok, privacy: .public) authorize.url.valid=\(hasAuthorizeURL, privacy: .public)")
    }

    static func sessionCreated() {
        log.info("[BrokerOAuth] session.created")
    }

    static func presentationAnchor(available: Bool) {
        log.info("[BrokerOAuth] presentationAnchor.available=\(available, privacy: .public)")
    }

    static func sessionStart(result: Bool) {
        log.info("[BrokerOAuth] session.start result=\(result, privacy: .public)")
    }

    static func callbackReceived(_ received: Bool) {
        log.info("[BrokerOAuth] callback received=\(received, privacy: .public)")
    }

    static func callbackStatus(_ status: String?) {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "present" : "missing"
        log.info("[BrokerOAuth] callback status=\(value, privacy: .public)")
    }

    static func cancelled() {
        log.info("[BrokerOAuth] cancelled")
    }

    static func error(type: String) {
        log.error("[BrokerOAuth] error=\(type, privacy: .public)")
    }
}
#else
nonisolated enum BrokerOAuthDebugLog {
    static func tap() {}
    static func authorizeRequest(client: String, bodyIncluded: Bool) {}
    static func authorizeResponse(status: Int, ok: Bool, hasAuthorizeURL: Bool) {}
    static func sessionCreated() {}
    static func presentationAnchor(available: Bool) {}
    static func sessionStart(result: Bool) {}
    static func callbackReceived(_ received: Bool) {}
    static func callbackStatus(_ status: String?) {}
    static func cancelled() {}
    static func error(type: String) {}
}
#endif
