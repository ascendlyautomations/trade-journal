import SwiftUI
import UIKit

/// Bio editor that blocks a 4th line at input time (Return does nothing at the 3-line cap).
struct ProfileBioTextField: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat?
    var maxHeight: CGFloat?
    var onEditingBegan: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var resolvedMinHeight: CGFloat {
        minHeight ?? 44
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            bioEditor
            HStack {
                Spacer(minLength: 0)
                Text(ProfileBioPolicy.characterCounterLabel(for: text))
                    .font(.caption2)
                    .foregroundStyle(counterColor)
                    .accessibilityIdentifier("profile.bio.characterCounter")
            }
        }
    }

    @ViewBuilder
    private var bioEditor: some View {
        let representable = ProfileBioTextViewRepresentable(
            text: $text,
            placeholder: placeholder,
            minHeight: minHeight,
            maxHeight: maxHeight,
            onEditingBegan: onEditingBegan,
            onEditingEnded: onEditingEnded
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: resolvedMinHeight, alignment: .top)

        if let maxHeight {
            representable.frame(maxHeight: maxHeight, alignment: .top)
        } else {
            representable
        }
    }

    private var counterColor: Color {
        let limit = ProfileBioPolicy.maximumAllowedCharacterCount()
        let count = ProfileBioPolicy.characterCount(for: text)
        if count >= limit {
            return colors.tertiaryText
        }
        return colors.secondaryText.opacity(0.9)
    }
}

private struct ProfileBioTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat?
    var maxHeight: CGFloat?
    var onEditingBegan: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onEditingBegan: onEditingBegan,
            onEditingEnded: onEditingEnded
        )
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
        textView.accessibilityIdentifier = "profile.bio.editor"
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
        context.coordinator.updateEditingHandlers(
            onEditingBegan: onEditingBegan,
            onEditingEnded: onEditingEnded
        )
        uiView.placeholderLabel.text = placeholder
        let width = Self.contentWidth(for: uiView)
        let display = ProfileBioPolicy.constrained(text, contentWidth: width)
        if uiView.textView.text != display {
            uiView.textView.text = display
        }
        uiView.updatePlaceholderVisibility()
        uiView.minHeight = minHeight
        uiView.maxHeight = maxHeight
        uiView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BioTextViewContainer, context: Context) -> CGSize? {
        let proposed = proposal.replacingUnspecifiedDimensions()
        let width = proposed.width.isFinite && proposed.width > 0
            ? proposed.width
            : ProfileBioPolicy.referenceContentWidth()
        uiView.bounds.size = CGSize(width: width, height: proposed.height)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        let height = uiView.intrinsicContentSize.height
        return CGSize(width: width, height: max(height, minHeight ?? 44))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var onEditingBegan: (() -> Void)?
        private var onEditingEnded: (() -> Void)?
        private weak var container: BioTextViewContainer?

        init(
            text: Binding<String>,
            onEditingBegan: (() -> Void)?,
            onEditingEnded: (() -> Void)?
        ) {
            self.text = text
            self.onEditingBegan = onEditingBegan
            self.onEditingEnded = onEditingEnded
        }

        func updateEditingHandlers(
            onEditingBegan: (() -> Void)?,
            onEditingEnded: (() -> Void)?
        ) {
            self.onEditingBegan = onEditingBegan
            self.onEditingEnded = onEditingEnded
        }

        func attach(container: BioTextViewContainer) {
            self.container = container
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onEditingBegan?()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onEditingEnded?()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText string: String
        ) -> Bool {
            let current = textView.text ?? ""
            let width = contentWidth(for: container)
            switch ProfileBioPolicy.editDecision(
                current: current,
                range: range,
                replacement: string,
                contentWidth: width
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
            let width = contentWidth(for: container)
            let capped = ProfileBioPolicy.constrained(raw, contentWidth: width)
            if capped != raw {
                textView.text = capped
            }
            if text.wrappedValue != capped {
                text.wrappedValue = capped
            }
            container?.updatePlaceholderVisibility()
            container?.invalidateIntrinsicContentSize()
        }

        private func contentWidth(for container: BioTextViewContainer?) -> CGFloat {
            guard let width = container?.bounds.width, width > 0 else {
                return ProfileBioPolicy.referenceContentWidth()
            }
            return width
        }
    }

    private static func contentWidth(for container: BioTextViewContainer) -> CGFloat {
        let width = container.bounds.width
        if width > 0 { return width }
        return ProfileBioPolicy.referenceContentWidth()
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
        let width = bounds.width > 0 ? bounds.width : ProfileBioPolicy.defaultReferenceScreenWidth
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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) {
            return hit
        }
        guard bounds.contains(point) else { return nil }
        return textView
    }
}
