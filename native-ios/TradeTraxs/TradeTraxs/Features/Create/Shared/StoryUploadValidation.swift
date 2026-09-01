import Foundation

/// Client-side guards — mirrors web `lib/uploadValidation.ts` (`validateImageUpload`).
enum StoryUploadValidation {
    static let maxBytes = 15 * 1024 * 1024

    private static let allowedMIME: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/gif",
    ]

    private static let allowedExtensions: Set<String> = [
        ".jpg", ".jpeg", ".png", ".webp", ".gif",
    ]

    static func validate(data: Data, contentType: String?, fileName: String?) -> String? {
        if data.isEmpty {
            return "File is empty."
        }
        if data.count > maxBytes {
            let maxMB = maxBytes / (1024 * 1024)
            return "Image must be \(maxMB) MB or smaller."
        }

        let mime = contentType?.lowercased() ?? ""
        if !mime.isEmpty, allowedMIME.contains(mime) {
            return nil
        }

        if let ext = fileExtension(fileName), allowedExtensions.contains(ext) {
            return nil
        }

        if mime.hasPrefix("video/") {
            return "File must be an image (JPEG, PNG, WebP, or GIF)."
        }
        if mime.hasPrefix("image/") {
            return "Unsupported image format. Use JPEG, PNG, WebP, or GIF."
        }
        return "File must be an image (JPEG, PNG, WebP, or GIF)."
    }

    private static func fileExtension(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let idx = name.lastIndex(of: ".")
        guard let idx else { return nil }
        return String(name[idx...]).lowercased()
    }
}
