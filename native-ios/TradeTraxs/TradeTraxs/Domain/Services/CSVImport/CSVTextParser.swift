import Foundation

/// PapaParse-style CSV → rows of string dictionaries (header row required).
///
/// RFC4180 parsing uses `UnicodeScalar` (not Swift `Character`) so CRLF is two scalars,
/// not one grapheme cluster — otherwise record boundaries are invisible to the parser.
nonisolated enum CSVTextParser {
    private static let comma = UnicodeScalar(0x2C)!
    private static let quote = UnicodeScalar(0x22)!

    static func parse(text: String) throws -> (headers: [String], rows: [[String: String]]) {
        let scalars = unicodeScalars(strippingBOM: text)
        #if DEBUG
        CSVStringLineEndingCounts.logDecodeShape(byteCount: text.utf8.count, text: text)
        #endif
        let delimiter = detectDelimiter(scalars)
        let records = parseRecords(scalars, delimiter: delimiter)
        #if DEBUG
        let headerColumnCount = records.first?.count ?? 0
        let dataRowCount = max(0, records.filter { record in
            record.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.count - 1)
        print(
            "[CSV] records=\(records.count) headerColumns=\(headerColumnCount) dataRows=\(dataRowCount)"
        )
        #endif
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

    static func logDecodedShape(byteCount: Int, text: String) {
        #if DEBUG
        CSVStringLineEndingCounts.logDecodeShape(byteCount: byteCount, text: text)
        let boundary = firstRecordBoundaryScalarOffset(in: text)
        print("[CSV] firstRecordBoundaryScalarOffset=\(boundary.map(String.init) ?? "none")")
        #endif
    }

    private static func unicodeScalars(strippingBOM text: String) -> [UnicodeScalar] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" {
            scalars.removeFirst()
        }
        return scalars
    }

    private static func detectDelimiter(_ scalars: [UnicodeScalar]) -> UnicodeScalar {
        let sample = firstRecordSample(scalars)
        let candidates: [UnicodeScalar] = [comma, "\t", ";", "|"]
        var best = comma
        var bestCount = 0
        for candidate in candidates {
            let count = sample.unicodeScalars.reduce(0) { $0 + ($1 == candidate ? 1 : 0) }
            if count > bestCount {
                bestCount = count
                best = candidate
            }
        }
        return best
    }

    private static func firstRecordSample(_ scalars: [UnicodeScalar]) -> String {
        var inQuotes = false
        var i = 0
        var sampleScalars: [UnicodeScalar] = []
        var skippingLeadingBlank = true
        while i < scalars.count {
            let s = scalars[i]
            if s == quote {
                skippingLeadingBlank = false
                if inQuotes, i + 1 < scalars.count, scalars[i + 1] == quote {
                    sampleScalars.append(s)
                    i += 1
                } else {
                    inQuotes.toggle()
                    sampleScalars.append(s)
                }
                i += 1
            } else if let advance = recordTerminatorAdvance(at: i, in: scalars, inQuotes: inQuotes) {
                if skippingLeadingBlank || String(String.UnicodeScalarView(sampleScalars))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    sampleScalars = []
                    skippingLeadingBlank = true
                    i = advance
                } else {
                    break
                }
            } else {
                if !Character(s).isWhitespace { skippingLeadingBlank = false }
                sampleScalars.append(s)
                i += 1
            }
        }
        return String(String.UnicodeScalarView(sampleScalars))
    }

    /// Index after consuming a record terminator, or nil if not at a terminator.
    private static func recordTerminatorAdvance(
        at i: Int,
        in scalars: [UnicodeScalar],
        inQuotes: Bool
    ) -> Int? {
        guard !inQuotes, i < scalars.count else { return nil }
        let s = scalars[i]
        if s == "\r" {
            if i + 1 < scalars.count, scalars[i + 1] == "\n" {
                return i + 2
            }
            return i + 1
        }
        if s == "\n" { return i + 1 }
        if s == "\u{0085}" || s == "\u{2028}" || s == "\u{2029}" {
            return i + 1
        }
        return nil
    }

    private static func parseRecords(_ scalars: [UnicodeScalar], delimiter: UnicodeScalar) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var currentScalars: [UnicodeScalar] = []
        var inQuotes = false
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == quote {
                if inQuotes, i + 1 < scalars.count, scalars[i + 1] == quote {
                    currentScalars.append(quote)
                    i += 2
                    continue
                }
                inQuotes.toggle()
                i += 1
            } else if s == delimiter && !inQuotes {
                row.append(String(String.UnicodeScalarView(currentScalars)))
                currentScalars = []
                i += 1
            } else if let advance = recordTerminatorAdvance(at: i, in: scalars, inQuotes: inQuotes) {
                row.append(String(String.UnicodeScalarView(currentScalars)))
                records.append(row)
                row = []
                currentScalars = []
                i = advance
            } else {
                currentScalars.append(s)
                i += 1
            }
        }
        if !currentScalars.isEmpty || !row.isEmpty {
            row.append(String(String.UnicodeScalarView(currentScalars)))
            records.append(row)
        }
        return records
    }

    private static func stripBOM(_ s: String) -> String {
        if s.unicodeScalars.first == "\u{FEFF}" {
            return String(s.unicodeScalars.dropFirst())
        }
        return s
    }

    #if DEBUG
    private static func firstRecordBoundaryScalarOffset(in text: String) -> Int? {
        let scalars = unicodeScalars(strippingBOM: text)
        var inQuotes = false
        var i = 0
        var offset = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == quote {
                if inQuotes, i + 1 < scalars.count, scalars[i + 1] == quote {
                    i += 2
                } else {
                    inQuotes.toggle()
                    i += 1
                }
            } else if recordTerminatorAdvance(at: i, in: scalars, inQuotes: inQuotes) != nil {
                return offset
            } else {
                i += 1
            }
            offset += 1
        }
        return nil
    }
    #endif
}
