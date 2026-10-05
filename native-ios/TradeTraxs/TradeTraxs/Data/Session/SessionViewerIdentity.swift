import Foundation

/// Journal viewer identity. A missing user id stays unavailable.
/// Fixture identities are only returned for Demo Mode or an explicit DEBUG screenshot launch.
nonisolated enum SessionViewerIdentity {
    static let screenshotFixtureProfileID = ProfileID("dev.screenshot")
    static let sessionUnavailableMessage = "Your session isn't ready yet."

    enum Resolution: Equatable {
        case viewer(ProfileID)
        case unavailable
    }

    static func resolve(
        userID: UserID?,
        demoExperienceActive: Bool,
        screenshotFixturesEnabled: Bool = ScreenshotFixtureAccess.isEnabled
    ) -> Resolution {
        if let userID {
            let profileID = ProfileID(userID.rawValue)
            // A real session wins, including Explore as Guest. The bundled demo
            // identity is only used when there is no real user id.
            if !demoExperienceActive || !DemoExperienceSupport.usesLocalBundledData(profileID) {
                return .viewer(profileID)
            }
        }
        if demoExperienceActive {
            return .viewer(DemoExperienceSupport.profileID)
        }
        if screenshotFixturesEnabled {
            return .viewer(screenshotFixtureProfileID)
        }
        return .unavailable
    }

    /// A fixture load may commit only while it is still the live viewer.
    static func shouldCommit(
        resolved: ProfileID,
        userID: UserID?,
        demoExperienceActive: Bool,
        screenshotFixturesEnabled: Bool = ScreenshotFixtureAccess.isEnabled
    ) -> Bool {
        guard case .viewer(let current) = resolve(
            userID: userID,
            demoExperienceActive: demoExperienceActive,
            screenshotFixturesEnabled: screenshotFixturesEnabled
        ) else {
            return false
        }
        return current == resolved
    }
}

nonisolated enum ScreenshotFixtureAccess {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uitesting-") }
        #else
        false
        #endif
    }
}
