import SwiftUI
import UIKit

/// True when the feed timeline is the active visible tab surface (impressions only while active).
@MainActor
enum FeedImpressionVisibility {
    static var feedSurfaceActive = false
}

struct FeedImpressionTrackingModifier: ViewModifier {
    let contentKind: String
    let contentID: String
    @State private var visibleFraction: CGFloat = 0
    @State private var dwellTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateVisibility(frame: proxy.frame(in: .global)) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in
                            updateVisibility(frame: frame)
                        }
                }
            }
            .onDisappear {
                dwellTask?.cancel()
                dwellTask = nil
            }
    }

    private func updateVisibility(frame: CGRect) {
        guard FeedImpressionVisibility.feedSurfaceActive,
              BackendV2FeatureFlags.isEnabled(.feedRotatingRank)
        else {
            dwellTask?.cancel()
            dwellTask = nil
            return
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first
        else { return }
        let intersection = frame.intersection(window.bounds)
        guard frame.height > 1 else { return }
        let ratio = intersection.height / frame.height
        visibleFraction = ratio
        if ratio >= 0.5 {
            guard dwellTask == nil else { return }
            dwellTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, visibleFraction >= 0.5 else { return }
                FeedImpressionCoordinator.shared.trackVisibleContent(
                    kind: contentKind,
                    contentID: contentID
                )
            }
        } else {
            dwellTask?.cancel()
            dwellTask = nil
        }
    }
}

extension View {
    func feedImpressionTracked(contentKind: String, contentID: String) -> some View {
        modifier(FeedImpressionTrackingModifier(contentKind: contentKind, contentID: contentID))
    }
}