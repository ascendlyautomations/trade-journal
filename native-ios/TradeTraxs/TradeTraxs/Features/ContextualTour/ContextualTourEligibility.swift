import CoreGraphics
import Foundation
import os
import SwiftUI

enum ContextualTourEligibility {
    /// Missing or unparsed account age is not eligible. Pre-cutoff accounts are grandfathered.
    static func isAccountEligible(createdAt: Date?, cutoff: Date) -> Bool {
        guard let createdAt else { return false }
        return createdAt >= cutoff
    }

    static func shouldAutomaticallyPresent(
        createdAt: Date?,
        cutoff: Date,
        dismissedVersion: Int,
        tourVersion: Int
    ) -> Bool {
        guard isAccountEligible(createdAt: createdAt, cutoff: cutoff) else { return false }
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
    static let resolveTimeout: TimeInterval = 1.2

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

    /// A target is ready only after two usable, agreeing frames. A timeout skips it.
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
        let intersection = visible.intersection(frame)
        if intersection.isNull || intersection.isEmpty { return true }
        return intersection.height < frame.height * 0.6 || intersection.width < frame.width * 0.6
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

    /// Exact Debug console markers for the zero-trade overlay test.
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
    var profileRootActive = false
    var settingsHomeActive = false
    var sceneActive = false
    var unobstructed = false

    /// Dashboard auto-start still requires the home root. Later steps use their own surface.
    var allowsPresentation: Bool {
        homeRootActive && sceneActive && unobstructed
    }
}
