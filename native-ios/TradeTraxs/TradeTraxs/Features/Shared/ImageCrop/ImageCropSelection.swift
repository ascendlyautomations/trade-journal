import PhotosUI
import SwiftUI
import UIKit

/// Presents the shared crop editor after photo selection (Feed/Profile original + crop metadata).
struct ImageCropSelectionModifier: ViewModifier {
    @Binding var cropSourceImage: UIImage?
    let preset: ImageCropEditorPreset
    let onConfirm: (ImageCropSelectionResult) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: {
                    cropSourceImage.map(ImageCropSheetItem.init(image:))
                },
                set: { newValue in
                    if newValue == nil {
                        cropSourceImage = nil
                    }
                }
            )) { item in
                ImageCropEditorView(
                    sourceImage: item.image,
                    preset: preset,
                    onCancel: {
                        cropSourceImage = nil
                        onCancel()
                    },
                    onConfirmFeed: { result in
                        onConfirm(result)
                        cropSourceImage = nil
                    }
                )
            }
    }
}

/// Presents the crop editor for avatar/room flows that export a baked image.
struct ImageCropSelectionBakedModifier: ViewModifier {
    @Binding var cropSourceImage: UIImage?
    let preset: ImageCropEditorPreset
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: {
                    cropSourceImage.map(ImageCropSheetItem.init(image:))
                },
                set: { newValue in
                    if newValue == nil {
                        cropSourceImage = nil
                    }
                }
            )) { item in
                ImageCropEditorView(
                    sourceImage: item.image,
                    preset: preset,
                    onCancel: {
                        cropSourceImage = nil
                        onCancel()
                    },
                    onConfirmBaked: { image in
                        onConfirm(image)
                        cropSourceImage = nil
                    }
                )
            }
    }
}

private struct ImageCropSheetItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension View {
    func imageCropSelection(
        sourceImage: Binding<UIImage?>,
        preset: ImageCropEditorPreset,
        onConfirm: @escaping (ImageCropSelectionResult) -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            ImageCropSelectionModifier(
                cropSourceImage: sourceImage,
                preset: preset,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }

    func imageCropSelectionBaked(
        sourceImage: Binding<UIImage?>,
        preset: ImageCropEditorPreset,
        onConfirm: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            ImageCropSelectionBakedModifier(
                cropSourceImage: sourceImage,
                preset: preset,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }
}

