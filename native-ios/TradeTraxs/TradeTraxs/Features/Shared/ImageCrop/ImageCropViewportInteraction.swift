import SwiftUI
import UIKit

/// Pan + pinch inside the fixed crop viewport — anchor-aware pinch in viewport coordinates.
struct ImageCropViewportInteraction: UIViewRepresentable {
    let onPanBegan: () -> Void
    let onPan: (_ translationDelta: CGSize) -> Void
    let onPanEnded: () -> Void
    let onPinchBegan: (_ anchorInViewport: CGPoint) -> Void
    let onPinch: (_ magnification: CGFloat, _ anchorInViewport: CGPoint) -> Void
    let onPinchEnded: () -> Void

    func makeUIView(context: Context) -> ImageCropViewportInteractionView {
        let view = ImageCropViewportInteractionView()
        view.onPanBegan = onPanBegan
        view.onPan = onPan
        view.onPanEnded = onPanEnded
        view.onPinchBegan = onPinchBegan
        view.onPinch = onPinch
        view.onPinchEnded = onPinchEnded
        return view
    }

    func updateUIView(_ uiView: ImageCropViewportInteractionView, context: Context) {
        uiView.onPanBegan = onPanBegan
        uiView.onPan = onPan
        uiView.onPanEnded = onPanEnded
        uiView.onPinchBegan = onPinchBegan
        uiView.onPinch = onPinch
        uiView.onPinchEnded = onPinchEnded
    }
}

final class ImageCropViewportInteractionView: UIView, UIGestureRecognizerDelegate {
    var onPanBegan: (() -> Void)?
    var onPan: ((_ translationDelta: CGSize) -> Void)?
    var onPanEnded: (() -> Void)?
    var onPinchBegan: ((_ anchorInViewport: CGPoint) -> Void)?
    var onPinch: ((_ magnification: CGFloat, _ anchorInViewport: CGPoint) -> Void)?
    var onPinchEnded: (() -> Void)?

    private var panRecognizer: UIPanGestureRecognizer!
    private var pinchRecognizer: UIPinchGestureRecognizer!
    private weak var parentScrollView: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panRecognizer.delegate = self
        panRecognizer.maximumNumberOfTouches = 1
        addGestureRecognizer(panRecognizer)

        pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchRecognizer.delegate = self
        addGestureRecognizer(pinchRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        parentScrollView = findParentScrollView()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            parentScrollView?.isScrollEnabled = false
            onPanBegan?()
        case .changed:
            let delta = recognizer.translation(in: self)
            onPan?(CGSize(width: delta.x, height: delta.y))
        case .ended, .cancelled, .failed:
            parentScrollView?.isScrollEnabled = true
            onPanEnded?()
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let anchor = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            parentScrollView?.isScrollEnabled = false
            onPinchBegan?(anchor)
        case .changed:
            onPinch?(recognizer.scale, anchor)
        case .ended, .cancelled, .failed:
            parentScrollView?.isScrollEnabled = true
            onPinchEnded?()
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === panRecognizer && otherGestureRecognizer === pinchRecognizer
            || gestureRecognizer === pinchRecognizer && otherGestureRecognizer === panRecognizer
    }

    private func findParentScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
