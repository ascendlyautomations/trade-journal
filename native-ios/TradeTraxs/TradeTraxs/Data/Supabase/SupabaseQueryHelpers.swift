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
