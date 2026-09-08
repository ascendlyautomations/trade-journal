import Foundation

nonisolated enum SupabaseQuery {
    static func page(_ request: PageRequest, orderColumn: String = "created_at") -> [URLQueryItem] {
        page(request, orderColumn: orderColumn, ascending: false)
    }

    /// Keyset page helper — `ascending` flips order + cursor comparator (`gt` vs `lt`).
    static func page(
        _ request: PageRequest,
        orderColumn: String,
        ascending: Bool
    ) -> [URLQueryItem] {
        let direction = ascending ? "asc" : "desc"
        let comparator = ascending ? "gt" : "lt"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "order", value: "\(orderColumn).\(direction)"),
            URLQueryItem(name: "limit", value: String(request.limit)),
        ]
        if let cursor = request.cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "\(orderColumn)", value: "\(comparator).\(cursor)"))
        }
        return items
    }

    static func eq(_ column: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value)")
    }

    /// PostgREST `column=in.(a,b,c)`.
    static func isIn(_ column: String, _ values: [String]) -> URLQueryItem {
        let joined = values.joined(separator: ",")
        return URLQueryItem(name: column, value: "in.(\(joined))")
    }

    static func select(_ columns: String) -> URLQueryItem {
        URLQueryItem(name: "select", value: columns)
    }

    static func nextCursor<T>(
        items: [T],
        limit: Int,
        cursor: (T) -> String?
    ) -> String? {
        guard items.count >= limit, let last = items.last else { return nil }
        return cursor(last)
    }

    /// Parses `created_at|id` keyset cursors from RPC bootstrap and REST pagination.
    static func parseCreatedAtIDCursor(_ cursor: String) -> (createdAt: String, id: String?) {
        let parts = cursor.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return (cursor, nil)
    }

    /// Keyset page for `(created_at desc, id desc)` — matches profile bootstrap pagination.
    static func createdAtIDPage(_ request: PageRequest) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "order", value: "created_at.desc,id.desc"),
            URLQueryItem(name: "limit", value: String(request.limit)),
        ]
        if let cursor = request.cursor, !cursor.isEmpty {
            items.append(contentsOf: keysetBeforeCreatedAtID(cursor))
        }
        return items
    }

    /// Rows strictly before `(createdAt, id)` in descending `(created_at, id)` order.
    static func keysetBeforeCreatedAtID(_ cursor: String) -> [URLQueryItem] {
        let parsed = parseCreatedAtIDCursor(cursor)
        if let id = parsed.id, !id.isEmpty {
            let filter = "(created_at.lt.\(parsed.createdAt),and(created_at.eq.\(parsed.createdAt),id.lt.\(id)))"
            return [URLQueryItem(name: "or", value: filter)]
        }
        return [URLQueryItem(name: "created_at", value: "lt.\(parsed.createdAt)")]
    }

    static func nextCreatedAtIDCursor<T>(
        items: [T],
        limit: Int,
        createdAt: (T) -> String?,
        id: (T) -> String?
    ) -> String? {
        guard items.count >= limit, let last = items.last else { return nil }
        guard let createdAt = createdAt(last), !createdAt.isEmpty,
              let id = id(last), !id.isEmpty
        else { return nil }
        return "\(createdAt)|\(id)"
    }
}

extension Array {
    /// Bounded PostgREST `in.()` batches (URL length / payload).
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
