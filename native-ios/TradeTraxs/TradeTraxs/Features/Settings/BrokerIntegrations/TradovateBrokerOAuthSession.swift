@preconcurrency import AuthenticationServices
import Foundation
import UIKit

/// Presents Tradovate OAuth via BFF-issued authorize URL — no broker tokens on device.
@MainActor
enum TradovateBrokerOAuthSession {
    static func connect(authorizeURL: URL) async -> TradovateBrokerOAuthOutcome {
        let presenter = TradovateBrokerOAuthPresenter()
        do {
            let callbackURL = try await presenter.start(url: authorizeURL)
            BrokerOAuthDebugLog.callbackReceived(true)
            let items = NativeOAuthConfiguration.fragmentOrQueryItems(from: callbackURL)
            let status = items["status"]?.lowercased()
            BrokerOAuthDebugLog.callbackStatus(status)
            if status == "success" {
                return .success
            }
            return .error(reason: items["reason"])
        } catch let error as AppError {
            if case .cancelled = error {
                BrokerOAuthDebugLog.cancelled()
                return .cancelled
            }
            if case .authentication(.cancelled) = error {
                BrokerOAuthDebugLog.cancelled()
                return .cancelled
            }
            BrokerOAuthDebugLog.error(type: "AppError")
            return .error(reason: UserFacingError.message(for: error))
        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            {
                BrokerOAuthDebugLog.cancelled()
                return .cancelled
            }
            BrokerOAuthDebugLog.error(type: String(describing: type(of: error)))
            return .error(reason: error.localizedDescription)
        }
    }
}

/// Retains ``ASWebAuthenticationSession`` and presentation context until OAuth completes.
@MainActor
private final class TradovateBrokerOAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let bridge = OAuthWebAuthenticationSessionBridge()

    func start(url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                bridge.bind(continuation: continuation)
                BrokerOAuthDebugLog.sessionCreated()

                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: NativeOAuthConfiguration.callbackScheme
                ) { [weak self] callbackURL, error in
                    guard let self else { return }
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                        {
                            _ = self.bridge.finishOnce(
                                with: .failure(AppError.cancelled),
                                source: .userCancellation
                            )
                        } else {
                            _ = self.bridge.finishOnce(
                                with: .failure(error),
                                source: .sessionError
                            )
                        }
                        return
                    }
                    guard let callbackURL else {
                        _ = self.bridge.finishOnce(
                            with: .failure(AppError.unknown(message: "Tradovate sign-in did not return a callback.")),
                            source: .missingCallbackURL
                        )
                        return
                    }
                    guard NativeOAuthConfiguration.isTradovateBrokerOAuthCallbackURL(callbackURL) else {
                        _ = self.bridge.finishOnce(
                            with: .failure(AppError.unknown(message: "Unexpected Tradovate return URL.")),
                            source: .invalidCallbackURL
                        )
                        return
                    }
                    _ = self.bridge.finishOnce(with: .success(callbackURL), source: .callbackSuccess)
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                bridge.attach(session: session)

                DispatchQueue.main.async {
                    let anchor = self.presentationAnchor(for: session)
                    let anchorValid = anchor.windowScene != nil || anchor.isKeyWindow
                    BrokerOAuthDebugLog.presentationAnchor(available: anchorValid)
                    let started = session.start()
                    BrokerOAuthDebugLog.sessionStart(result: started)
                    if !started {
                        _ = self.bridge.finishOnce(
                            with: .failure(AppError.unknown(message: "Could not open Tradovate sign-in.")),
                            source: .startFailed
                        )
                    }
                }
            }
        } onCancel: {
            _ = self.bridge.finishOnce(
                with: .failure(AppError.cancelled),
                source: .taskCancellation
            )
            self.bridge.cancelSession()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        if let window = scenes.flatMap(\.windows).first {
            return window
        }
        return UIWindow()
    }
}
