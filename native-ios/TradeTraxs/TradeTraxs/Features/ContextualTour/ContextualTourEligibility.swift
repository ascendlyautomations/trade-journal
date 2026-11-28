import CoreGraphics
import Foundation
import os
import SwiftUI

enum ContextualTourEligibility {
    /// Epoch fallback from bootstrap means unknown age, not a pre-cutoff account.
    static func isAuthoritativeCreatedAt(_ createdAt: Date?) -> Bool {
        guard let createdAt else { return false }
        return createdAt.timeIntervalSince1970 > 1
    }

    /// Missing or unparsed account age is not eligible. Pre-cutoff accounts are grandfathered.
    static func isAccountEligible(createdAt: Date?, cutoff: Date) -> Bool {
        guard isAuthoritativeCreatedAt(createdAt), let createdAt else { return false }
        return createdAt >= cutoff
    }

    static func shouldAutomaticallyPresent(
        createdAt: Date?,
        cutoff: Date,
        dismissedVersion: Int,
        tourVersion: Int
    ) -> Bool {
        _ = createdAt
        _ = cutoff
        return dismissedVersion < tourVersion
    }
}

enum ContextualTourTargetResolution: Equatable {
    case waiting
    case ready(CGRect)
    case skip
}

enum ContextualTourGeometry {
    static let stabilityTolerance: CGFloat = 1
    static let resolveTimeout: TimeInterval = 0.45

    static func resolveTimeout(for target: ContextualTourTargetID?) -> TimeInterval {
        switch target {
        case .dashboardCalendar, .feedExplore, .feedTradeRooms, .profileInsights, .profileSettings:
            return 0.65
        case .mainTabHome, .mainTabFeed, .mainTabCreate, .mainTabMessages, .mainTabProfile:
            return 0.55
        default:
            return resolveTimeout
        }
    }

    static func isUsable(_ frame: CGRect) -> Bool {
        frame.width > 1
            && frame.height > 1
            && frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
    }

    /// A real control, including one that is still below the fold. Not the full screen.
    static func isMeasurableTarget(_ frame: CGRect, in viewport: CGRect) -> Bool {
        guard isUsable(frame), isUsable(viewport) else { return false }
        let coversScreen = frame.width >= viewport.width * 0.98
            && frame.height >= viewport.height * 0.85
        return !coversScreen
    }

    /// A spotlight hole must be a real on-screen control, not the full container.
    static func isRenderableSpotlight(_ frame: CGRect, in viewport: CGRect) -> Bool {
        guard isMeasurableTarget(frame, in: viewport) else { return false }
        let nearby = viewport.insetBy(dx: -32, dy: -32)
        return nearby.intersects(frame)
    }

    static func isStable(_ previous: CGRect, _ current: CGRect) -> Bool {
        abs(previous.minX - current.minX) <= stabilityTolerance
            && abs(previous.minY - current.minY) <= stabilityTolerance
            && abs(previous.width - current.width) <= stabilityTolerance
            && abs(previous.height - current.height) <= stabilityTolerance
    }

    /// A target is ready only after two usable, agreeing frames. A timeout skips it (test helper).
    static func resolve(
        frame: CGRect?,
        previous: CGRect?,
        elapsed: TimeInterval,
        timeout: TimeInterval = resolveTimeout
    ) -> ContextualTourTargetResolution {
        if let frame, isUsable(frame), let previous, isUsable(previous), isStable(previous, frame) {
            return .ready(frame)
        }
        if elapsed >= timeout {
            return .skip
        }
        return .waiting
    }

    /// Two-frame stability for spotlight layout updates while presenting.
    @discardableResult
    static func recordStabilityCandidate(_ frame: CGRect, previous: inout CGRect?) -> Bool {
        guard isUsable(frame) else { return false }
        if let previous, isUsable(previous), isStable(previous, frame) {
            return true
        }
        previous = frame
        return false
    }

    /// Profile header targets stay at the top; autoscroll fights shell loading and causes flicker.
    static func skipsTourAutoscroll(for target: ContextualTourTargetID) -> Bool {
        switch target {
        case .profileIdentity, .profileTradeRoom, .profileInsights, .profileSettings,
             .mainTabHome, .mainTabFeed, .mainTabCreate, .mainTabMessages, .mainTabProfile:
            return true
        default:
            return false
        }
    }

    /// Extra clearance so settings rows are not treated as visible under the navigation bar.
    static func measurementTopInset(for target: ContextualTourTargetID?) -> CGFloat {
        switch target {
        case .dashboardAccountAndDates:
            return ContextualTourCardPlacement.navigationClearance + ExperienceSpacing.sm
        case .settingsAppearance, .settingsTradingRules:
            return ContextualTourCardPlacement.navigationClearance
        default:
            return 0
        }
    }

    /// Keeps settings rows out of the tab bar column when the tour overlays the main shell.
    static func measurementBottomInset(for target: ContextualTourTargetID?) -> CGFloat {
        switch target {
        case .settingsAppearance, .settingsTradingRules:
            return 49 + ExperienceSpacing.md
        case .mainTabHome, .mainTabFeed, .mainTabCreate, .mainTabMessages, .mainTabProfile:
            return ExperienceSpacing.xs
        default:
            return 0
        }
    }

    /// Toolbar glyph targets: measure the visible icon, not the bar button container.
    static let toolbarIconSpotlightTargets: Set<ContextualTourTargetID> = [
        .dashboardCalendar,
        .profileInsights,
        .profileSettings,
    ]

    /// Pre-padding square measurement for `profileSettings` (toolbar gear glyph).
    static func profileSettingsToolbarGlyphSpotlightMeasurementFrame(_ glyphFrame: CGRect) -> CGRect {
        let side = max(glyphFrame.width, glyphFrame.height)
        let center = CGPoint(x: glyphFrame.midX, y: glyphFrame.midY)
        return CGRect(
            x: center.x - side * 0.5,
            y: center.y - side * 0.5,
            width: side,
            height: side
        )
    }

    static func profileSettingsToolbarGlyphSpotlightHolePadding() -> (horizontal: CGFloat, vertical: CGFloat) {
        (ExperienceSpacing.sm, ExperienceSpacing.sm)
    }

    /// Same final hole height as `profileSettings`; width follows the Trade Rooms glyph (no `max(width,height)` square).
    static func feedTradeRoomsToolbarGlyphSpotlightMeasurementFrame(glyphFrame: CGRect) -> CGRect {
        let capHeight = max(glyphFrame.height, 1)
        let settingsHeight = profileSettingsToolbarGlyphSpotlightMeasurementFrame(
            CGRect(
                x: glyphFrame.midX,
                y: glyphFrame.midY,
                width: capHeight,
                height: capHeight
            )
        ).height
        let width = max(glyphFrame.width, 1)
        return CGRect(
            x: glyphFrame.midX - width * 0.5,
            y: glyphFrame.midY - settingsHeight * 0.5,
            width: width,
            height: settingsHeight
        )
    }

    /// Square frame centered on the measured icon bounds so spotlight padding is even on all sides.
    static func refinedSpotlightFrame(_ frame: CGRect, for target: ContextualTourTargetID?) -> CGRect {
        guard let target, isUsable(frame) else { return frame }
        if target == .feedTradeRooms {
            return feedTradeRoomsToolbarGlyphSpotlightMeasurementFrame(glyphFrame: frame)
        }
        if target == .profileSettings {
            return profileSettingsToolbarGlyphSpotlightMeasurementFrame(frame)
        }
        guard toolbarIconSpotlightTargets.contains(target) else { return frame }
        let side = max(frame.width, frame.height)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return CGRect(
            x: center.x - side * 0.5,
            y: center.y - side * 0.5,
            width: side,
            height: side
        )
    }

    static func spotlightScrimOpacity(colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? 0.74 : 0.55
    }

    static func spotlightHolePadding(for target: ContextualTourTargetID?) -> (horizontal: CGFloat, vertical: CGFloat) {
        if target?.isMainTabBarTarget == true {
            return (ExperienceSpacing.xxs, ExperienceSpacing.xxs)
        }
        switch target {
        case .feedContentFilters:
            return (ExperienceSpacing.xxs, ExperienceSpacing.xxs)
        case .feedTradeRooms:
            return profileSettingsToolbarGlyphSpotlightHolePadding()
        case .dashboardCalendar, .profileInsights, .profileSettings:
            let pad = ExperienceSpacing.sm
            return (pad, pad)
        default:
            return (ExperienceSpacing.xs, ExperienceSpacing.xs)
        }
    }

    static func needsScroll(
        frame: CGRect,
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> Bool {
        let visible = CGRect(
            x: viewport.minX,
            y: viewport.minY + topInset,
            width: viewport.width,
            height: max(0, viewport.height - topInset - bottomInset)
        )
        if isRenderableSpotlight(frame, in: visible) {
            return false
        }
        let intersection = visible.intersection(frame)
        if intersection.isNull || intersection.isEmpty { return true }
        return intersection.height < frame.height * 0.6 || intersection.width < frame.width * 0.6
    }

    /// Tall dashboard sections read better with a top anchor; compact controls stay centered.
    static func scrollAnchor(for target: ContextualTourTargetID) -> UnitPoint {
        switch target {
        case .dashboardAccountAndDates:
            return UnitPoint(x: 0.5, y: 0.14)
        case .dashboardGettingStarted,
             .dashboardPerformance,
             .dashboardTrades,
             .dashboardReports,
             .dashboardWithdrawals,
             .payoutsHistory,
             .expenseTrackerAdd,
             .expenseTrackerIncome,
             .expenseTrackerAnalytics,
             .expenseTrackerExport:
            return .top
        case .settingsAppearance:
            return UnitPoint(x: 0.5, y: 0.72)
        case .settingsTradingRules:
            return UnitPoint(x: 0.5, y: 0.38)
        default:
            return .center
        }
    }

    static func measurementVisibleRect(
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGRect {
        CGRect(
            x: viewport.minX,
            y: viewport.minY + topInset,
            width: viewport.width,
            height: max(0, viewport.height - topInset - bottomInset)
        )
    }

    /// Tab-bar spotlights live in chrome excluded by scroll measurement insets; use the full overlay viewport.
    static func spotlightMeasurementVisibleRect(
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat,
        target: ContextualTourTargetID?
    ) -> CGRect {
        if target?.isMainTabBarTarget == true {
            return viewport
        }
        return measurementVisibleRect(viewport: viewport, topInset: topInset, bottomInset: bottomInset)
    }
}

enum ContextualTourMotion {
    /// Reduce Motion crossfades the spotlight. Otherwise the hole eases between targets.
    static func spotlightAnimation(reduceMotion: Bool) -> Animation? {
        ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion)
    }

    static func prefersCrossfade(reduceMotion: Bool) -> Bool {
        reduceMotion
    }
}

nonisolated enum ContextualTourDebug {
    nonisolated private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "ContextualTour"
    )
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastMessage = ""
    nonisolated(unsafe) private static var lastAppTourMessage = ""
    nonisolated(unsafe) private static var lastMeasureReject = ""
    nonisolated(unsafe) private static var lastTourTraceLine = ""

    nonisolated static func logAppTour(_ message: String) {
        #if DEBUG
        let line = "[APP_TOUR] \(message)"
        lock.lock()
        defer { lock.unlock() }
        guard line != lastAppTourMessage else { return }
        lastAppTourMessage = line
        print(line)
        #else
        _ = message
        #endif
    }

    nonisolated static func log(_ message: String) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        guard message != lastMessage else { return }
        lastMessage = message
        logger.debug("\(message, privacy: .public)")
        #else
        _ = message
        #endif
    }

    /// Activation → render pipeline tracing. Consecutive identical lines are suppressed unless `force` is set.
    nonisolated static func logTourTrace(_ message: String, force: Bool = false) {
        #if DEBUG
        let line = "[TOUR_TRACE] \(message)"
        lock.lock()
        defer { lock.unlock() }
        if !force, line == lastTourTraceLine { return }
        lastTourTraceLine = line
        print(line)
        logger.debug("\(line, privacy: .public)")
        #else
        _ = message
        #endif
    }

    nonisolated static func logMeasureReject(_ reason: String) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let line = "[Walkthrough][measure] reject \(reason)"
        guard line != lastMeasureReject else { return }
        lastMeasureReject = line
        logger.debug("\(line, privacy: .public)")
        print(line)
        #else
        _ = reason
        #endif
    }

    nonisolated static func logPhaseTransition(_ from: String, _ to: String, _ detail: String) {
        #if DEBUG
        log("[Walkthrough][phase] \(from) -> \(to) (\(detail))")
        #else
        _ = from
        _ = to
        _ = detail
        #endif
    }

    nonisolated static func logMarker(_ message: String) {
        #if DEBUG
        let line = "[ContextualTour] \(message)"
        lock.lock()
        defer { lock.unlock() }
        guard line != lastMessage else { return }
        lastMessage = line
        print(line)
        logger.debug("\(line, privacy: .public)")
        #else
        _ = message
        #endif
    }
}

struct ContextualTourGates: Equatable, Sendable {
    var homeRootActive = false
    var feedRootActive = false
    var messagesRootActive = false
    var profileRootActive = false
    var settingsHomeActive = false
    var payoutsActive = false
    var expenseTrackerActive = false
    var tradesActive = false
    var sceneActive = false
    var unobstructed = false

    /// Dashboard auto-start still requires the home root. Later steps use their own surface.
    var allowsPresentation: Bool {
        homeRootActive && sceneActive && unobstructed
    }
}
