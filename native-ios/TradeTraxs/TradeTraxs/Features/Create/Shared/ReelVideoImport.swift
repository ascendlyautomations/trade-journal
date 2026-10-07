import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One-shot Photos / local file import into TradeTraxs-owned temporary storage.
///
/// After import completes, callers must never touch ``PhotosPickerItem`` again.
enum ReelVideoImport {
    struct OwnedSource: Sendable {
        var selectionID: String
        var url: URL
        var contentType: String
        var byteCount: Int
    }

    /// Provider temp file retained after duration preflight when PhotoKit metadata was unavailable.
    struct PreflightedPickerMovie: Sendable {
        var url: URL
    }

    private static let importFolderName = "TradeTraxsReelImport"

    static func importDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(importFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func ownedSourceURL(selectionID: String, fileExtension: String) throws -> URL {
        let ext = fileExtension.isEmpty ? "mov" : fileExtension
        return try importDirectory()
            .appendingPathComponent("source-\(selectionID).\(ext)", isDirectory: false)
    }

    /// When PhotoKit duration is missing, loads the provider once and validates duration before any owned copy.
    static func preflightPhotosPickerMovie(_ item: PhotosPickerItem) async throws -> PreflightedPickerMovie? {
        try VideoUploadDurationValidation.throwIfPhotoLibraryExceedsReelUploadLimit(item)
        if VideoUploadDurationValidation.photoLibraryDurationSeconds(for: item) != nil {
            return nil
        }

        VideoImportDiagnostics.logProviderLoadStarted(id: "preflight")
        do {
            guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
                throw AppError.unknown(message: "Couldn't read that video. Try MP4 or MOV.")
            }
            try await VideoUploadDurationValidation.validateReelUploadDuration(at: movie.url)
            return PreflightedPickerMovie(url: movie.url)
        } catch {
            VideoImportDiagnostics.logImportFailed(
                id: "preflight",
                stage: "providerLoad",
                message: sanitized(error.localizedDescription)
            )
            throw error
        }
    }

    static func releasePreflightedPickerMovie(_ movie: PreflightedPickerMovie?) {
        cleanup(url: movie?.url)
    }

    /// Loads the movie representation exactly once, then copies into app-owned storage.
    static func importFromPhotosPicker(
        _ item: PhotosPickerItem,
        selectionID: String,
        prefetchedMovie: PreflightedPickerMovie? = nil
    ) async throws -> OwnedSource {
        if prefetchedMovie == nil {
            try VideoUploadDurationValidation.throwIfPhotoLibraryExceedsReelUploadLimit(item)
        }

        let providerURL: URL
        if let prefetchedMovie {
            providerURL = prefetchedMovie.url
            VideoImportDiagnostics.logProviderLoadCompleted(id: selectionID)
        } else {
            VideoImportDiagnostics.logProviderLoadStarted(id: selectionID)
            do {
                guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
                    throw AppError.unknown(message: "Couldn't read that video. Try MP4 or MOV.")
                }
                providerURL = movie.url
                VideoImportDiagnostics.logProviderLoadCompleted(id: selectionID)
            } catch {
                VideoImportDiagnostics.logImportFailed(
                    id: selectionID,
                    stage: "providerLoad",
                    message: sanitized(error.localizedDescription)
                )
                throw error
            }
            try await VideoUploadDurationValidation.validateReelUploadDuration(at: providerURL)
        }

        defer {
            VideoImportDiagnostics.logProviderReleased(id: selectionID)
            cleanup(url: providerURL)
        }

        VideoImportDiagnostics.logOwnedCopyStarted(id: selectionID)
        let owned = try copyToOwnedStorage(
            from: providerURL,
            selectionID: selectionID,
            contentTypeHint: "video/quicktime"
        )
        VideoImportDiagnostics.logOwnedCopyCompleted(id: selectionID, bytes: owned.byteCount)
        return owned
    }

    /// Camera / file URLs may be ephemeral — copy immediately into app-owned storage.
    static func importFromLocalFile(
        _ url: URL,
        contentType: String?,
        selectionID: String
    ) async throws -> OwnedSource {
        try await VideoUploadDurationValidation.validateReelUploadDuration(at: url)
        VideoImportDiagnostics.logOwnedCopyStarted(id: selectionID)
        let owned = try copyToOwnedStorage(
            from: url,
            selectionID: selectionID,
            contentTypeHint: contentType
        )
        VideoImportDiagnostics.logOwnedCopyCompleted(id: selectionID, bytes: owned.byteCount)
        VideoImportDiagnostics.logProviderReleased(id: selectionID)
        return owned
    }

    static func cleanup(selectionID: String) {
        guard let directory = try? importDirectory() else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.contains(selectionID) {
            cleanup(url: file)
        }
    }

    nonisolated static func cleanup(url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func fileIsReadable(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0
    }

    // MARK: - Private

    private static func copyToOwnedStorage(
        from sourceURL: URL,
        selectionID: String,
        contentTypeHint: String?
    ) throws -> OwnedSource {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let ownedURL = try ownedSourceURL(selectionID: selectionID, fileExtension: ext)
        cleanup(url: ownedURL)
        try FileManager.default.copyItem(at: sourceURL, to: ownedURL)

        let values = try ownedURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = values.fileSize ?? 0
        guard byteCount > 0 else {
            cleanup(url: ownedURL)
            throw AppError.unknown(message: "Could not read this video file.")
        }

        let contentType = MediaVideoPreparation.mimeType(
            forExtension: ext,
            fallback: contentTypeHint
        )
        return OwnedSource(
            selectionID: selectionID,
            url: ownedURL,
            contentType: contentType,
            byteCount: byteCount
        )
    }

    private static func sanitized(_ message: String) -> String {
        message
            .replacingOccurrences(
                of: #"https?://[^\s]+"#,
                with: "<url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"file://[^\s]+"#,
                with: "<file>",
                options: .regularExpression
            )
    }
}
