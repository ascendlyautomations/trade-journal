import Foundation

/// PapaParse-style CSV → rows of string dictionaries (header row required).
///
/// Matches web `Papa.parse({ header: true, skipEmptyLines: true })` plus
/// `normalizeParsedCsvRows`: RFC4180 quotes, auto delimiter, column alignment,
/// empty header keys dropped only after cells are assigned.
nonisolated enum CSVTextParser {
    static func parse(text: String) throws -> (headers: [String], rows: [[String: String]]) {
        let source = stripBOM(text)
        let delimiter = detectDelimiter(source)
        let records = parseRecords(source, delimiter: delimiter)
        let nonEmpty = records.filter { record in
            record.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let headerCells = nonEmpty.first else {
            throw AppError.unknown(message: "This CSV doesn't contain any trades.")
        }
        let rawHeaders = headerCells.map { stripBOM($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard rawHeaders.contains(where: { !$0.isEmpty }) else {
            throw AppError.unknown(message: "This CSV format isn't supported.")
        }

        var rows: [[String: String]] = []
        for record in nonEmpty.dropFirst() {
            var row: [String: String] = [:]
            var normalizedOwner: [String: String] = [:]
            for (index, header) in rawHeaders.enumerated() {
                guard !header.isEmpty else { continue }
                let value = index < record.count
                    ? record[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let normalized = CSVHeaderAliases.normalizeHeaderKey(header)
                if let previous = normalizedOwner[normalized], previous != header {
                    row.removeValue(forKey: previous)
                }
                normalizedOwner[normalized] = header
                row[header] = value
            }
            if row.values.contains(where: { !$0.isEmpty }) {
                rows.append(row)
            }
        }

        var seen = Set<String>()
        var headers: [String] = []
        for header in rawHeaders where !header.isEmpty && seen.insert(header).inserted {
            headers.append(header)
        }

        #if DEBUG
        print("[CSV] total CSV rows=\(nonEmpty.count - 1) candidate rows=\(rows.count)")
        #endif
        return (headers, rows)
    }

    /// Papa guesses `,`, tab, `;`, or `|` from the first non-empty record.
    private static func detectDelimiter(_ text: String) -> Character {
        let sample = firstRecordSample(text)
        let candidates: [Character] = [",", "\t", ";", "|"]
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates {
            let count = sample.filter { $0 == candidate }.count
            if count > bestCount {
                bestCount = count
                best = candidate
            }
        }
        return best
    }

    private static func firstRecordSample(_ text: String) -> String {
        var inQuotes = false
        var index = text.startIndex
        var sample = ""
        var skippingLeadingBlank = true
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" {
                skippingLeadingBlank = false
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    sample.append(ch)
                    index = next
                } else {
                    inQuotes.toggle()
                    sample.append(ch)
                }
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                if skippingLeadingBlank || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sample = ""
                    skippingLeadingBlank = true
                    if ch == "\r" {
                        let next = text.index(after: index)
                        if next < text.endIndex, text[next] == "\n" { index = next }
                    }
                } else {
                    break
                }
            } else {
                if !ch.isWhitespace { skippingLeadingBlank = false }
                sample.append(ch)
            }
            index = text.index(after: index)
        }
        return sample
    }

    /// One pass so escaped quotes (`""`) stay inside a field and do not swallow later rows.
    private static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var current = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" {
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == delimiter && !inQuotes {
                row.append(current)
                current = ""
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                if ch == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(current)
                records.append(row)
                row = []
                current = ""
            } else {
                current.append(ch)
            }
            index = text.index(after: index)
        }
        if !current.isEmpty || !row.isEmpty {
            row.append(current)
            records.append(row)
        }
        return records
    }

    private static func stripBOM(_ s: String) -> String {
        if s.first == "\u{FEFF}" { return String(s.dropFirst()) }
        return s
    }
}
