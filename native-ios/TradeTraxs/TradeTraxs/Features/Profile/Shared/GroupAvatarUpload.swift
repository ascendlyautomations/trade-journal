import Foundation
import UIKit

/// Group conversation avatar JPEG upload (`group-avatars` bucket, web path parity).
enum GroupAvatarUpload {
    static func upload(
        jpegData: Data,
        conversationID: ConversationID,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        supabaseURL: URL? = nil
    ) async throws -> String {
        let payload = try ProfileAvatarUpload.jpegUploadPayload(from: jpegData)
        let path = StorageOptimizedMedia.objectPath(
            prefix: conversationID.rawValue,
            fileExtension: "jpg"
        )
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.groupAvatars.rawValue,
                path: path,
                data: payload,
                contentType: "image/jpeg",
                purpose: .profileAvatar,
                cacheControl: "3600"
            )
        )
        if let url = objectStorage.publicURL(
            bucket: StorageBucket.groupAvatars.rawValue,
            path: reference.id
        )?.absoluteString {
            return url
        }
        if let base = supabaseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            return "\(base)/storage/v1/object/public/group-avatars/\(reference.id)"
        }
        return reference.id
    }
}