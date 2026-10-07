import SwiftUI
import UIKit

/// Scrolls the whole comment composer into view while the keyboard is opening.
///
/// SwiftUI's focused-field scroll only clears the caret, which leaves the bottom of the
/// text box and Send button under the keyboard. This reveals the composer container instead.
struct CommentComposerKeyboardVisibility: UIViewRepresentable {
    func makeUIView(context: Context) -> ComposerVisibilityView {
        ComposerVisibilityView()
    }

    func updateUIView(_ uiView: ComposerVisibilityView, context: Context) {}
}

final class ComposerVisibilityView: UIView {
    private var observers: [NSObjectProtocol] = []
    private var lastCover: CGFloat = 0
    private var lastHostHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        let center = NotificationCenter.default
        observers = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardDidShowNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.revealIfKeyboardOpening(notification)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let host = composerHost() else { return }
        let height = host.bounds.height
        guard abs(height - lastHostHeight) > 8 else { return }
        lastHostHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.revealComposer(animated: false)
        }
    }

    private func revealIfKeyboardOpening(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenHeight = window?.bounds.height ?? UIScreen.main.bounds.height
        let cover = max(0, screenHeight - frame.minY)
        let opening = cover > lastCover + 1
        lastCover = cover
        guard opening, composerIsFocused() else { return }
        revealComposer(animated: false)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.composerIsFocused() else { return }
            self.revealComposer(animated: false)
        }
    }

    private func revealComposer(animated: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        guard let host = composerHost() else { return }
        let rect = host.convert(host.bounds, to: scrollView)
        guard rect.height > 1, rect.height < 360 else { return }
        scrollView.scrollRectToVisible(rect, animated: animated)
    }

    private func composerIsFocused() -> Bool {
        composerHost() != nil
    }

    /// Largest composer-sized ancestor that contains the focused field, stopping at the scroll view.
    private func composerHost() -> UIView? {
        var current: UIView? = self
        var best: UIView?
        while let view = current {
            if view is UIScrollView { break }
            if view !== self,
               view.bounds.height > 20,
               view.bounds.height < 360,
               view.containsFirstResponder() {
                best = view
            }
            current = view.superview
        }
        return best
    }

    private var enclosingScrollView: UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }
}

private extension UIView {
    func containsFirstResponder() -> Bool {
        if isFirstResponder { return true }
        return subviews.contains { $0.containsFirstResponder() }
    }
}
