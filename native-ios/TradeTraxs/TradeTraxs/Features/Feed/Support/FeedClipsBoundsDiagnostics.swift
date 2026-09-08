import CoreGraphics
import Foundation
import SwiftUI

enum FeedClipsBoundsRole: String {
    case categoryBar
    case pager
}

private struct FeedClipsBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func feedClipsBoundsAnchor(_ role: FeedClipsBoundsRole) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FeedClipsBoundsPreferenceKey.self,
                    value: [role.rawValue: geometry.frame(in: .global)]
                )
            }
        }
    }

    func feedClipsBoundsLogging(isEnabled: Bool) -> some View {
        onPreferenceChange(FeedClipsBoundsPreferenceKey.self) { frames in
            guard isEnabled else { return }
            FeedClipsLayoutDiagnostics.logBounds(frames: frames)
        }
    }
}

#if DEBUG
extension FeedClipsLayoutDiagnostics {
    static func logBounds(frames: [String: CGRect]) {
        let categoryBar = frames[FeedClipsBoundsRole.categoryBar.rawValue]
        let pager = frames[FeedClipsBoundsRole.pager.rawValue]
        let tabBarTop = UITabBar.feedClipsTopInKeyWindow()

        print("[ClipsBounds] categoryBarBottomY=\(categoryBar?.maxY ?? -1)")
        print("[ClipsBounds] pagerTopY=\(pager?.minY ?? -1)")
        print("[ClipsBounds] pagerBottomY=\(pager?.maxY ?? -1)")
        print("[ClipsBounds] bottomTabBarTopY=\(tabBarTop ?? -1)")
        print("[ClipsBounds] pagerHeight=\(pager?.height ?? -1)")
        print("[ClipsBounds] pageHeight=\(pager?.height ?? -1)")
    }
}
#else
extension FeedClipsLayoutDiagnostics {
    static func logBounds(frames: [String: CGRect]) {}
}
#endif
