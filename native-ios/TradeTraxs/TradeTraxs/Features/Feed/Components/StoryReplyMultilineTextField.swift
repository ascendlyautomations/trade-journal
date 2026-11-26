import SwiftUI
import UIKit

/// Story reply field — UIKit text view with no keyboard accessory (matches DM / Trade Room).
struct StoryReplyMultilineTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isEnabled: Bool
    var onSubmit: () -> Void

    private let maxLines = 4

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            maxLines: maxLines,
            onSubmit: onSubmit
        )
    }

    func makeUIView(context: Context) -> ExperienceNoKeyboardAccessoryTextView {
        let textView = ExperienceNoKeyboardAccessoryTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .white
        textView.tintColor = .white
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityIdentifier = "feed.story.replyField"
        context.coordinator.attach(textView)
        return textView
    }

    func updateUIView(_ textView: ExperienceNoKeyboardAccessoryTextView, context: Context) {
        context.coordinator.attach(textView)
        context.coordinator.isProgrammaticFocusChange = true
        defer { context.coordinator.isProgrammaticFocusChange = false }

        if textView.text != text {
            textView.text = text
        }
        textView.isEditable = isEnabled

        if isFocused, !textView.isFirstResponder, isEnabled {
            _ = textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        let maxLines: Int
        let onSubmit: () -> Void

        var isProgrammaticFocusChange = false
        private weak var textView: ExperienceNoKeyboardAccessoryTextView?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            maxLines: Int,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.maxLines = maxLines
            self.onSubmit = onSubmit
        }

        func attach(_ textView: ExperienceNoKeyboardAccessoryTextView) {
            self.textView = textView
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            ExperienceKeyboardAccessoryStrip.clearOnFirstResponderIfNeeded()
            if !isProgrammaticFocusChange, !isFocused {
                isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if !isProgrammaticFocusChange, isFocused {
                isFocused = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text ?? ""
            clampLinesIfNeeded(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText string: String
        ) -> Bool {
            if string == "\n" {
                onSubmit()
                return false
            }
            return true
        }

        private func clampLinesIfNeeded(_ textView: UITextView) {
            guard let font = textView.font else { return }
            let maxHeight = font.lineHeight * CGFloat(maxLines) + textView.textContainerInset.top
                + textView.textContainerInset.bottom + 4
            if textView.contentSize.height > maxHeight {
                textView.isScrollEnabled = true
                textView.showsVerticalScrollIndicator = false
            } else {
                textView.isScrollEnabled = false
            }
        }
    }
}