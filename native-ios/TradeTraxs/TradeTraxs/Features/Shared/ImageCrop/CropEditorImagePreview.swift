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

#if DEBUG
struct CropEditorDebugOverlay: View {
    let viewportSize: CGSize

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.red.opacity(0.85), lineWidth: 1)

            Path { path in
                let midX = viewportSize.width / 2
                let midY = viewportSize.height / 2
                path.move(to: CGPoint(x: midX, y: 0))
                path.addLine(to: CGPoint(x: midX, y: viewportSize.height))
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: viewportSize.width, y: midY))

                for fraction in [0.25, 0.75] {
                    let y = viewportSize.height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: viewportSize.width, y: y))
                }
            }
            .stroke(Color.yellow.opacity(0.7), lineWidth: 0.75)
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .allowsHitTesting(false)
    }
}
#endif

struct CropViewportSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
