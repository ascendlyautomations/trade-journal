import Foundation

nonisolated enum ProfilePinnedContentRepository {
    static func pin(
        request: ProfilePinRequest,
        supabase: SupabaseInfrastructure
    ) async throws -> [ProfilePinnedItem] {
        var payload: [String: Any] = [
            "p_content_type": request.contentType.rawValue,
            "p_content_id": request.contentID,
        ]
        if let replace = request.replacePosition {
            payload["p_replace_position"] = replace
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try await fetchPins(
            functionName: BackendV2Versioning.RPCName.profilePinContent.rawValue,
            parametersJSON: body,
            supabase: supabase
        )
    }

    static func unpin(
        contentType: ProfilePinnedContentType,
        contentID: String,
        supabase: SupabaseInfrastructure
    ) async throws -> [ProfilePinnedItem] {
        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_content_type": contentType.rawValue,
                "p_content_id": contentID,
            ],
            options: []
        )
        return try await fetchPins(
            functionName: BackendV2Versioning.RPCName.profileUnpinContent.rawValue,
            parametersJSON: body,
            supabase: supabase
        )
    }

    static func reorder(
        fromPosition: Int,
        toPosition: Int,
        supabase: SupabaseInfrastructure
    ) async throws -> [ProfilePinnedItem] {
        let body = try JSONSerialization.data(
            withJSONObject: [
                "p_from_position": fromPosition,
                "p_to_position": toPosition,
            ],
            options: []
        )
        return try await fetchPins(
            functionName: BackendV2Versioning.RPCName.profileReorderPinned.rawValue,
            parametersJSON: body,
            supabase: supabase
        )
    }

    static func mapPins(from wire: [ProfilePinnedWireV1]?) -> [ProfilePinnedItem] {
        (wire ?? []).compactMap { row in
            guard let type = ProfilePinnedContentType.parse(row.content_type),
                  let contentID = row.content_id,
                  let position = row.position,
                  let previewWire = row.preview
            else { return nil }
            return ProfilePinnedItem(
                contentType: type,
                contentID: contentID,
                position: position,
                preview: ProfilePinnedPreview(
                    kindLabel: previewWire.kind_label ?? type.displayLabel,
                    title: previewWire.title ?? type.displayLabel,
                    subtitle: previewWire.subtitle,
                    imageURL: previewWire.image_url,
                    body: previewWire.body,
                    valueText: previewWire.value_text
                )
            )
        }
        .sorted { $0.position < $1.position }
    }

    private static func fetchPins(
        functionName: String,
        parametersJSON: Data,
        supabase: SupabaseInfrastructure
    ) async throws -> [ProfilePinnedItem] {
        struct Payload: Decodable {
            struct Meta: Decodable { var contract_version: String? }
            struct DataBlock: Decodable { var pins: [ProfilePinnedWireV1]? }
            var meta: Meta?
            var data: DataBlock?
        }

        let data = try await supabase.database.rpcData(
            functionName: functionName,
            parametersJSON: parametersJSON
        )
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let version = payload.meta?.contract_version {
            try BackendV2Versioning.assertContractVersion(version)
        }
        return mapPins(from: payload.data?.pins)
    }
}

nonisolated struct ProfilePinnedWireV1: Codable, Sendable, Equatable {
    var content_type: String?
    var content_id: String?
    var position: Int?
    var preview: ProfilePinnedPreviewWireV1?
}

nonisolated struct ProfilePinnedPreviewWireV1: Codable, Sendable, Equatable {
    var kind_label: String?
    var title: String?
    var subtitle: String?
    var image_url: String?
    var body: String?
    var value_text: String?
}
