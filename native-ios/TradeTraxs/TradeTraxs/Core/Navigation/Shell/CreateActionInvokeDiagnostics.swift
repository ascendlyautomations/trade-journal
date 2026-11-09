import Foundation
import OSLog
import UIKit

enum CreateActionSource: String, Sendable {
    case tabSelection
    case createTabGateShield
    case uiTestLaunch
    case unknown
}

struct CreateTabShieldTouchContext: Sendable, CustomStringConvertible {
    var swiftUINavigationGateEnabled: Bool
    var uiKitPolicyAllowed: Bool
    var tabBarHidden: Bool
    var tabBarAlpha: CGFloat
    var tabBarFrameInWindow: CGRect
    var shieldFrameInWindow: CGRect
    var touchPointInWindow: CGPoint
    var hitTestViewDescription: String
    var messagesPathDepth: Int
    var selectedTab: String

    var description: String {
        """
        swiftUIGate=\(swiftUINavigationGateEnabled) uiKitPolicy=\(uiKitPolicyAllowed) \
        tabHidden=\(tabBarHidden) tabAlpha=\(tabBarAlpha) \
        tabFrame=\(tabBarFrameInWindow.debugDescription) shieldFrame=\(shieldFrameInWindow.debugDescription) \
        touch=\(touchPointInWindow.debugDescription) hit=\(hitTestViewDescription) \
        messagesDepth=\(messagesPathDepth) tab=\(selectedTab)
        """
    }
}

enum CreateActionInvokeDiagnostics {
    private static let log = Logger(subsystem: "com.tradetraxs.app", category: "CreateAction")

    private(set) static var lastSource: CreateActionSource = .unknown
    private(set) static var lastShieldTouchContext: CreateTabShieldTouchContext?

    static func recordInvoke(source: CreateActionSource, detail: String = "") {
        lastSource = source
        #if DEBUG
        log.info("Create action invoked source=\(source.rawValue, privacy: .public) \(detail, privacy: .public)")
        #else
        log.info("Create action invoked source=\(source.rawValue, privacy: .public)")
        #endif
    }

    static func recordShieldTouch(_ context: CreateTabShieldTouchContext) {
        lastShieldTouchContext = context
        #if DEBUG
        log.info("Create tab shield touch \(context.description, privacy: .public)")
        #endif
    }
}
