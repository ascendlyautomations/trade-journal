import SwiftUI

#if DEBUG
enum FeedClipsPageMetricsStore {
    nonisolated(unsafe) static var sizes: [Int: CGSize] = [:]

    static func record(index: Int, size: CGSize) {
        sizes[index] = size
    }
}
#endif

/// Host root for a single Clips page — layout is exactly the UIKit page bounds, not the device screen.
struct FeedClipsPageHostRoot<Content: View>: View {
    let index: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea(.all, edges: .all)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        #if DEBUG
                        FeedClipsPageMetricsStore.record(index: index, size: geometry.size)
                        #endif
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        #if DEBUG
                        FeedClipsPageMetricsStore.record(index: index, size: newSize)
                        #endif
                    }
            }
        }
    }
}
