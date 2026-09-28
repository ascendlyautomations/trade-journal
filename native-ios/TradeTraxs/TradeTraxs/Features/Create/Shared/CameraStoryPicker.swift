import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Story camera — photo or video; recorded video is capped at ``StoryMediaDuration/maxVideoDurationSeconds``.
struct CameraStoryPicker: UIViewControllerRepresentable {
    var onPickedPhoto: (UIImage) -> Void
    var onPickedVideo: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = TimeInterval(StoryMediaDuration.maxVideoDurationSeconds)
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPickedPhoto: onPickedPhoto, onPickedVideo: onPickedVideo, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPickedPhoto: (UIImage) -> Void
        let onPickedVideo: (URL) -> Void
        let onCancel: () -> Void

        init(
            onPickedPhoto: @escaping (UIImage) -> Void,
            onPickedVideo: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPickedPhoto = onPickedPhoto
            self.onPickedVideo = onPickedVideo
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                onPickedVideo(url)
                return
            }
            if let image = info[.originalImage] as? UIImage {
                onPickedPhoto(image)
                return
            }
            onCancel()
        }
    }
}
