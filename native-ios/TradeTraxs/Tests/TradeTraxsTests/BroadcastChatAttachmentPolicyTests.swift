import XCTest
@testable import TradeTraxs

private struct StubObjectStorage: ObjectStorageProviding {
    let supabaseRoot: URL

    func publicURL(bucket: String, path: String) -> URL? {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var root = supabaseRoot.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/storage/v1/object/public/\(bucket)/\(cleaned)")
    }

    func upload(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String?
    ) async throws -> String {
        path
    }

    func upload(
        bucket: String,
        path: String,
        fileURL: URL,
        contentType: String,
        cacheControl: String?
    ) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data {
        Data()
    }

    func delete(bucket: String, path: String) async throws {}
}

final class BroadcastChatAttachmentPolicyTests: XCTestCase {
    func testResolvesStoragePathToHTTPSPublicURL() {
        let storage = StubObjectStorage(supabaseRoot: URL(string: "https://example.supabase.co")!)
        let path = "user-id/opt/123.jpg"
        let resolved = BroadcastChatAttachmentPolicy.resolvedAllowedBroadcastImageURL(
            path,
            objectStorage: storage
        )
        XCTAssertEqual(
            resolved,
            "https://example.supabase.co/storage/v1/object/public/screenshots/user-id/opt/123.jpg"
        )
    }

    func testPreservesValidHTTPSURL() {
        let storage = StubObjectStorage(supabaseRoot: URL(string: "https://example.supabase.co")!)
        let url = "https://cdn.example.com/a.jpg"
        XCTAssertEqual(
            BroadcastChatAttachmentPolicy.resolvedAllowedBroadcastImageURL(url, objectStorage: storage),
            url
        )
    }
}