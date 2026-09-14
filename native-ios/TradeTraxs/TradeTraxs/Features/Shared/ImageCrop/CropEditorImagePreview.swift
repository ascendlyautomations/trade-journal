import SwiftUI
import UIKit

/// UIKit crop preview — positions pixels with the same frame math used for export.
struct CropEditorImagePreview: UIViewRepresentable {
    let image: UIImage
    let geometry: CropViewportGeometry

    func makeUIView(context: Context) -> CropEditorImagePreviewView {
        let view = CropEditorImagePreviewView()
        view.clipsToBounds = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: CropEditorImagePreviewView, context: Context) {
        uiView.apply(image: image, geometry: geometry)
    }
}

final class CropEditorImagePreviewView: UIView {
    private let imageView = UIImageView()
    private var geometry: CropViewportGeometry?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(image: UIImage, geometry: CropViewportGeometry) {
        self.geometry = geometry
        imageView.image = image
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let geometry else { return }
        imageView.frame = geometry.previewImageFrame
    }
}

struct CropViewportSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
