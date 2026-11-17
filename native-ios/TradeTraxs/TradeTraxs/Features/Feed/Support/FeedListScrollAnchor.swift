import SwiftUI

/// Holds the Feed list scroll offset outside ``FeedScreenViewModel`` updates.
///
/// Scroll position writes stay on this object so list rows do not re-render on every
/// finger tick, and the restored offset is not reapplied during the gesture.
@MainActor
final class FeedListScrollAnchor {
    private var position: ScrollPosition
    private(set) var offset: CGFloat
    private var pendingRestoreOffset: CGFloat?
    private var restoreTaskGeneration: UInt64 = 0

    init(restoredOffset: CGFloat?) {
        if let restoredOffset {
            position = ScrollPosition(y: restoredOffset)
            offset = restoredOffset
        } else {
            position = ScrollPosition()
            offset = 0
        }
    }

    var binding: Binding<ScrollPosition> {
        Binding(
            get: { self.position },
            set: { newValue in
                let y = newValue.point?.y ?? self.offset
                self.offset = y
                if let x = newValue.point?.x, abs(x) > 0.5 {
                    self.position = ScrollPosition(y: y)
                } else {
                    self.position = newValue
                }
            }
        )
    }

    func resetToTop() {
        cancelPendingRestore()
        position = ScrollPosition()
        offset = 0
    }

    func noteMeasuredContentOffset(_ y: CGFloat) {
        guard y.isFinite else { return }
        guard y >= 0 else { return }
        offset = y
    }

    func applyRetainedOffset(_ y: CGFloat) {
        guard y > 0.5 else { return }
        cancelPendingRestore()
        offset = y
        position = ScrollPosition(y: y)
        pendingRestoreOffset = y
    }

    /// Reapplies the retained offset across layout passes (LazyVStack / navigation return).
    func scheduleLayoutStableRestore() {
        guard let y = pendingRestoreOffset, y > 0.5 else { return }
        restoreTaskGeneration &+= 1
        let generation = restoreTaskGeneration
        Task { @MainActor in
            for pass in 0..<6 {
                guard generation == restoreTaskGeneration else { return }
                position = ScrollPosition(y: y)
                try? await Task.sleep(nanoseconds: UInt64(24_000_000 + pass * 12_000_000))
            }
            guard generation == restoreTaskGeneration else { return }
            pendingRestoreOffset = nil
        }
    }

    private func cancelPendingRestore() {
        restoreTaskGeneration &+= 1
        pendingRestoreOffset = nil
    }
}