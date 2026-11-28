import SwiftUI
import UIKit

enum ExperienceActivityIndicatorMetrics {
    static func uiKitStyle(for controlSize: ControlSize) -> UIActivityIndicatorView.Style {
        switch controlSize {
        case .large, .extraLarge:
            return .large
        default:
            return .medium
        }
    }

    /// Approximates SwiftUI `ProgressView` `controlSize` layout.
    static func layoutScale(for controlSize: ControlSize) -> CGFloat {
        switch controlSize {
        case .mini:
            return 0.65
        case .small:
            return 0.85
        case .regular:
            return 1
        case .large:
            return 1
        case .extraLarge:
            return 1.12
        @unknown default:
            return 1
        }
    }
}

/// UIKit indeterminate spinner (no SwiftUI `ProgressView` "…" caption slot).
private struct ExperienceActivityIndicatorRepresentable: UIViewRepresentable {
    var color: Color
    var controlSize: ControlSize
    var isAnimating: Bool

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: ExperienceActivityIndicatorMetrics.uiKitStyle(for: controlSize))
        view.color = UIColor(color)
        view.isAccessibilityElement = false
        view.hidesWhenStopped = false
        setAnimating(isAnimating, on: view)
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        let style = ExperienceActivityIndicatorMetrics.uiKitStyle(for: controlSize)
        if uiView.style != style {
            uiView.style = style
        }
        uiView.color = UIColor(color)
        setAnimating(isAnimating, on: uiView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIActivityIndicatorView,
        context: Context
    ) -> CGSize? {
        uiView.sizeThatFits(
            CGSize(
                width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                height: proposal.height ?? UIView.layoutFittingExpandedSize.height
            )
        )
    }

    static func dismantleUIView(_ uiView: UIActivityIndicatorView, coordinator: ()) {
        uiView.stopAnimating()
    }

    private func setAnimating(_ animating: Bool, on view: UIActivityIndicatorView) {
        if animating {
            view.startAnimating()
        } else {
            view.stopAnimating()
        }
    }
}

/// Shared spinner chrome for design-system loading components.
struct ExperienceActivityIndicatorView: View {
    var controlSize: ControlSize = .regular
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ExperienceActivityIndicatorRepresentable(
            color: color,
            controlSize: controlSize,
            isAnimating: !reduceMotion
        )
        .fixedSize()
        .scaleEffect(ExperienceActivityIndicatorMetrics.layoutScale(for: controlSize))
        .accessibilityHidden(true)
    }
}