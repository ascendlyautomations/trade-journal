import Foundation

enum VaultDTO {
    nonisolated struct ItemRow: Decodable, Sendable {
        var id: String
        var user_id: String
        var content_type: String
        var content_id: String
        var created_at: String
    }

    nonisolated struct FolderRow: Decodable, Sendable {
        var id: String
        var user_id: String
        var name: String
        var created_at: String
        var updated_at: String
    }

    nonisolated struct FolderItemRow: Decodable, Sendable {
        var folder_id: String
        var vault_item_id: String
        var created_at: String
    }

    nonisolated struct InsertItemBody: Encodable, Sendable {
        var user_id: String
        var content_type: String
        var content_id: String
    }

    nonisolated struct InsertFolderBody: Encodable, Sendable {
        var user_id: String
        var name: String
    }

    nonisolated struct UpdateFolderBody: Encodable, Sendable {
        var name: String
        var updated_at: String
    }

    nonisolated struct InsertFolderItemBody: Encodable, Sendable {
        var folder_id: String
        var vault_item_id: String
    }

    nonisolated struct StateBatchItem: Encodable, Sendable {
        var content_type: String
        var content_id: String
    }

    nonisolated struct StateBatchWire: Decodable, Sendable {
        var content_type: String
        var content_id: String
        var vault_item_id: String
        var folder_ids: [String]?
    }
}
