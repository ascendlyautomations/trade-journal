import Foundation

/// Line-ending counts at UTF-8 and Unicode-scalar layers (not Swift `Character` graphemes).
nonisolated enum CSVStringLineEndingCounts {
    struct Counts: Sendable {
        var utf8LF: Int
        var utf8CR: Int
        var scalarLF: Int
        var scalarCR: Int
        var characterCount: Int
        var utf8ByteCount: Int
    }

    static func count(in text: String) -> Counts {
        var utf8LF = 0
        var utf8CR = 0
        for byte in text.utf8 {
            if byte == 0x0A { utf8LF += 1 }
            if byte == 0x0D { utf8CR += 1 }
        }
        var scalarLF = 0
        var scalarCR = 0
        for scalar in text.unicodeScalars {
            if scalar == "\n" { scalarLF += 1 }
            if scalar == "\r" { scalarCR += 1 }
        }
        return Counts(
            utf8LF: utf8LF,
            utf8CR: utf8CR,
            scalarLF: scalarLF,
            scalarCR: scalarCR,
            characterCount: text.count,
            utf8ByteCount: text.utf8.count
        )
    }

    #if DEBUG
    static func logDecodeShape(byteCount: Int, text: String) {
        let c = count(in: text)
        print(
            """
            [CSV_DECODE] utf8LF=\(c.utf8LF) utf8CR=\(c.utf8CR) scalarLF=\(c.scalarLF) scalarCR=\(c.scalarCR) \
            characters=\(c.characterCount) utf8Bytes=\(c.utf8ByteCount) rawBytes=\(byteCount)
            """
        )
    }
    #endif
}
