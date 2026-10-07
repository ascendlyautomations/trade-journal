import SwiftUI
import UIKit

/// Bio editor that blocks a 4th line at input time (Return does nothing at the 3-line cap).
struct ProfileBioTextField: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat?
    var maxHeight: CGFloat?

    var body: some View {
        ProfileBioTextViewRepresentable(
            text: $text,
            placeholder: placeholder,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }
}

private struct ProfileBioTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat?
    var maxHeight: CGFloat?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> BioTextViewContainer {
        let container = BioTextViewContainer()
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor.label
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        container.placeholderLabel.text = placeholder
        container.placeholderLabel.font = textView.font
        container.placeholderLabel.textColor = UIColor.placeholderText
        container.placeholderLabel.numberOfLines = 0
        container.updatePlaceholderVisibility()
        context.coordinator.attach(container: container)
        return container
    }

    func updateUIView(_ uiView: BioTextViewContainer, context: Context) {
        context.coordinator.attach(container: uiView)
        uiView.placeholderLabel.text = placeholder
        let display = ProfileBioPolicy.constrained(text)
        if uiView.textView.text != display {
            uiView.textView.text = display
        }
        uiView.updatePlaceholderVisibility()
        uiView.minHeight = minHeight
        uiView.maxHeight = maxHeight
        uiView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private weak var container: BioTextViewContainer?

        init(text: Binding<String>) {
            self.text = text
        }

        func attach(container: BioTextViewContainer) {
            self.container = container
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText string: String
        ) -> Bool {
            let current = textView.text ?? ""
            switch ProfileBioPolicy.editDecision(
                current: current,
                range: range,
                replacement: string
            ) {
            case .accept:
                return true
            case .reject:
                return false
            case .apply(let capped):
                textView.text = capped
                text.wrappedValue = capped
                container?.updatePlaceholderVisibility()
                let offset = min(range.location + (string as NSString).length, (capped as NSString).length)
                textView.selectedRange = NSRange(location: offset, length: 0)
                return false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            let raw = textView.text ?? ""
            let capped = ProfileBioPolicy.constrained(raw)
            if capped != raw {
                textView.text = capped
            }
            if text.wrappedValue != capped {
                text.wrappedValue = capped
            }
            container?.updatePlaceholderVisibility()
            container?.invalidateIntrinsicContentSize()
        }
    }
}

/// Hosts the text view + placeholder and reports a 3-line-friendly intrinsic height.
private final class BioTextViewContainer: UIView {
    let textView = UITextView()
    let placeholderLabel = UILabel()

    var minHeight: CGFloat?
    var maxHeight: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
        ])
        placeholderLabel.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updatePlaceholderVisibility() {
        let empty = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        placeholderLabel.isHidden = !empty
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        var height = fitting.height
        if let minHeight {
            height = max(height, minHeight)
        }
        if let maxHeight {
            height = min(height, maxHeight)
            textView.isScrollEnabled = fitting.height > maxHeight
        } else {
            textView.isScrollEnabled = false
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}
