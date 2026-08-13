import Foundation

/// Minimal RFC4180-style CSV → rows of string dictionaries (header row required).
nonisolated enum CSVTextParser {
    static func parse(text: String) throws -> (headers: [String], rows: [[String: String]]) {
        let lines = splitLines(stripBOM(text))
        guard let headerLine = lines.first else {
            throw AppError.unknown(message: "CSV file is empty.")
        }
        let headers = parseLine(headerLine).map { stripBOM($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !headers.isEmpty else {
            throw AppError.unknown(message: "CSV is missing a header row.")
        }

        var rows: [[String: String]] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let cells = parseLine(line)
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                let value = index < cells.count
                    ? cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                row[header] = value
            }
            if row.values.contains(where: { !$0.isEmpty }) {
                rows.append(row)
            }
        }
        return (headers, rows)
    }

    private static func stripBOM(_ s: String) -> String {
        if s.first == "\u{FEFF}" { return String(s.dropFirst()) }
        return s
    }

    private static func splitLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                if ch == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                lines.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = text.index(after: index)
        }
        if !current.isEmpty || !lines.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func parseLine(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = line.index(after: index)
        }
        cells.append(current)
        return cells
    }
}
