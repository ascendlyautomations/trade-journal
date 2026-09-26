import Foundation
import UIKit

/// Shared avatar JPEG upload path (onboarding + Settings → Profile).
enum ProfileAvatarUpload {
    static func upload(
        jpegData: Data,
        profileID: ProfileID,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        supabaseURL: URL?
    ) async throws -> String {
        let payload = try jpegUploadPayload(from: jpegData)
        let path = "\(profileID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.avatars.rawValue,
                path: path,
                data: payload,
                contentType: "image/jpeg",
                purpose: .profileAvatar
            )
        )
        if let url = objectStorage.publicURL(
            bucket: StorageBucket.avatars.rawValue,
            path: reference.id
        )?.absoluteString {
            return url
        }
        if let base = supabaseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            return "\(base)/storage/v1/object/public/avatars/\(reference.id)"
        }
        return reference.id
    }

    static func jpegUploadPayload(from data: Data) throws -> Data {
        if data.starts(with: [0xFF, 0xD8]) {
            return data
        }
        guard let image = UIImage(data: data),
              let jpeg = MediaImagePreparation.jpegData(from: image, maxDimension: 1200, quality: 0.92)
        else {
            struct InvalidAvatarPayload: Error {}
            throw InvalidAvatarPayload()
        }
        return jpeg
    }
}
