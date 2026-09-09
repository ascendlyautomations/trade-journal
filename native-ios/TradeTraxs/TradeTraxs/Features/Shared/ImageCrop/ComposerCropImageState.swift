import Foundation
import UIKit

/// Applies a physically cropped image to composer upload state — single entry point for create flows.
enum ComposerCropImageState {
    struct Applied: Sendable {
        let finalImage: UIImage
        let uploadData: Data
    }

    static func apply(_ result: ImageCropSelectionResult) -> Applied? {
        #if DEBUG
        CropDoneProbe.log(
            sourcePixels: result.sourcePixelSize,
            mode: result.aspectMode,
            result: result.image
        )
        #endif
        guard let uploadData = MediaImagePreparation.jpegData(
            from: result.image,
            logUpload: true
        ), !uploadData.isEmpty else {
            return nil
        }
        return Applied(finalImage: result.image, uploadData: uploadData)
    }
}

#if DEBUG
enum PostImageUploadProbe {
    static func log(finalImage: UIImage, uploadData: Data) {
        let pixels = MediaImageOrientation.pixelSize(of: finalImage)
        let aspect = pixels.width / max(pixels.height, 1)
        print(
            "[PostImageUpload] usingFinalCroppedImage=true "
                + "pixels=\(Int(pixels.width))x\(Int(pixels.height)) "
                + "aspect=\(String(format: "%.4f", aspect)) "
                + "bytes=\(uploadData.count)"
        )
    }
}
#else
enum PostImageUploadProbe {
    static func log(finalImage: UIImage, uploadData: Data) {}
}
#endif
