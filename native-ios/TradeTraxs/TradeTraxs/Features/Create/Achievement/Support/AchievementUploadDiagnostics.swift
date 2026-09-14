import Foundation

#if DEBUG
enum AchievementUploadDiagnostics {
    static func logBeforeStorageUpload(bytes: Int, request: URLRequest) {
        print(
            """
            [ACHIEVEMENT_UPLOAD] bytes=\(bytes) \
            requestHasHTTPBody=\(request.httpBody != nil) \
            requestHasHTTPBodyStream=\(request.httpBodyStream != nil)
            """
        )
    }

    static func logStorageUploadCompleted(path: String) {
        print("[ACHIEVEMENT_UPLOAD] storageCompleted path=\(path)")
    }

    static func logDatabaseCreated(achievementID: String) {
        print("[ACHIEVEMENT_UPLOAD] databaseCreated achievementID=\(achievementID)")
    }
}
#else
enum AchievementUploadDiagnostics {
    static func logBeforeStorageUpload(bytes: Int, request: URLRequest) {}
    static func logStorageUploadCompleted(path: String) {}
    static func logDatabaseCreated(achievementID: String) {}
}
#endif
