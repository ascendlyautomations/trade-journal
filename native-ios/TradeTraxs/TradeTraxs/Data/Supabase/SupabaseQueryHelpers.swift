import Foundation

nonisolated enum SupabaseQuery {
    static func page(_ page: PageRequest, orderColumn: String = "created_at") -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "order", value: "\(orderColumn).desc"),
            URLQueryItem(name: "limit", value: String(page.limit)),
        ]
        if let cursor = page.cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "\(orderColumn)", value: "lt.\(cursor)"))
        }
        return items
    }

    static func eq(_ column: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value)")
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
