import CryptoKit
import Foundation
import UniformTypeIdentifiers

#if DEBUG
/// Raw-byte inspection for CSV imports — counts and tiny hex windows only (never full file dumps).
nonisolated enum CSVRawFileDiagnostics {
    struct PickMetadata: Sendable {
        var fileName: String
        var pathExtension: String
        var byteCount: Int
        var securityScopedAccess: Bool
        var contentTypeIdentifier: String?
        var isUbiquitous: Bool?
        var fileResourceIdentifier: String?
        var ubiquitousDownloadStatus: String
    }

    static func logAfterRead(data: Data, url: URL, securityScopedAccess: Bool) {
        let meta = pickMetadata(data: data, url: url, securityScopedAccess: securityScopedAccess)
        logRawCounts(data: data, meta: meta)
        logBoundaryWindows(data: data)
        logDecoderCrossCheck(data: data)
    }

    static func pickMetadata(data: Data, url: URL, securityScopedAccess: Bool) -> PickMetadata {
        let values = try? url.resourceValues(forKeys: [
            .contentTypeKey,
            .isUbiquitousItemKey,
            .fileResourceIdentifierKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        let downloadStatus = values?.ubiquitousItemDownloadingStatus.map { String(describing: $0) } ?? "n/a"
        return PickMetadata(
            fileName: url.lastPathComponent,
            pathExtension: url.pathExtension,
            byteCount: data.count,
            securityScopedAccess: securityScopedAccess,
            contentTypeIdentifier: values?.contentType?.identifier,
            isUbiquitous: values?.isUbiquitousItem,
            fileResourceIdentifier: values?.fileResourceIdentifier?.debugDescription,
            ubiquitousDownloadStatus: downloadStatus
        )
    }

    private static func logRawCounts(data: Data, meta: PickMetadata) {
        let bom = detectBOM(data)
        let hexPrefix = hexString(data.prefix(16))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        print(
            """
            [CSV_RAW] bytes=\(meta.byteCount) bom=\(bom) hexPrefix=\(hexPrefix) sha256=\(sha.prefix(16))…
            [CSV_RAW] file=\(meta.fileName) ext=\(meta.pathExtension) scopedAccess=\(meta.securityScopedAccess) \
            uti=\(meta.contentTypeIdentifier ?? "nil") iCloud=\(String(describing: meta.isUbiquitous)) \
            ubiquitousDownload=\(meta.ubiquitousDownloadStatus)
            [CSV_RAW] byte0A=\(countByte(0x0A, in: data)) byte0D=\(countByte(0x0D, in: data)) \
            crlf=\(countSequence([0x0D, 0x0A], in: data))
            [CSV_RAW] utf16LE_LF=\(countSequence([0x0A, 0x00], in: data)) utf16LE_CR=\(countSequence([0x0D, 0x00], in: data)) \
            utf16BE_LF=\(countSequence([0x00, 0x0A], in: data)) utf16BE_CR=\(countSequence([0x00, 0x0D], in: data))
            """
        )
    }

    private static func logDecoderCrossCheck(data: Data) {
        guard let (text, encoding) = CSVTextDecoding.decodeWithEncoding(from: data) else {
            print("[CSV_RAW] decoder=failed")
            return
        }
        let endings = CSVStringLineEndingCounts.count(in: text)
        CSVStringLineEndingCounts.logDecodeShape(byteCount: data.count, text: text)
        let raw0A = countByte(0x0A, in: data)
        let raw0D = countByte(0x0D, in: data)
        let verdict: String
        if raw0A == 0, raw0D == 0, endings.scalarLF == 0, endings.scalarCR == 0 {
            verdict = "raw_already_flat"
        } else if raw0A == endings.utf8LF, raw0D == endings.utf8CR, endings.utf8LF > 0 || endings.utf8CR > 0 {
            verdict = "decoder_ok"
        } else if (raw0A > 0 || raw0D > 0), endings.scalarLF == 0, endings.scalarCR == 0 {
            verdict = "decoder_strips_or_wrong_encoding"
        } else {
            verdict = "inconclusive"
        }
        print("[CSV_RAW] decoder=\(encoding) verdict=\(verdict)")
    }

    private static func logBoundaryWindows(data: Data) {
        logBoundary(label: "durationBoundaryHex", data: data, needle: Data("duration".utf8))
        logBoundary(label: "durationValueBoundaryHex", data: data, needle: Data("21min 28sec".utf8))
        logBoundary(label: "mnqm6BoundaryHex", data: data, needle: Data("MNQM6".utf8), skipFirst: 1)
    }

    private static func logBoundary(label: String, data: Data, needle: Data, skipFirst: Int = 0) {
        guard let range = findOccurrence(needle, in: data, skip: skipFirst) else {
            print("[CSV_RAW] \(label)=needle_not_found")
            return
        }
        let start = range.upperBound
        let end = min(start + 24, data.count)
        guard start < end else {
            print("[CSV_RAW] \(label)=eof")
            return
        }
        let slice = data[start ..< end]
        let annotated = annotateBoundaryBytes(slice)
        print("[CSV_RAW] \(label)=\(hexString(slice)) \(annotated)")
    }

    private static func annotateBoundaryBytes(_ slice: Data.SubSequence) -> String {
        let labels = slice.map { byte -> String in
            switch byte {
            case 0x0A: return "LF"
            case 0x0D: return "CR"
            case 0x20: return "SP"
            case 0x09: return "TAB"
            case 0x00: return "NUL"
            default: return ""
            }
        }.filter { !$0.isEmpty }
        return labels.isEmpty ? "" : "(\(labels.joined(separator: ",")))"
    }

    private static func findOccurrence(_ needle: Data, in haystack: Data, skip: Int) -> Range<Data.Index>? {
        guard !needle.isEmpty else { return nil }
        var found = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, options: [], in: searchStart ..< haystack.endIndex)
        {
            if found >= skip {
                return range
            }
            found += 1
            searchStart = range.upperBound
        }
        return nil
    }

    private static func detectBOM(_ data: Data) -> String {
        guard data.count >= 2 else {
            if data.first == 0xEF, data.count >= 3, data[1] == 0xBB, data[2] == 0xBF { return "utf8" }
            return "none"
        }
        if data[0] == 0xEF, data[1] == 0xBB, data.count >= 3, data[2] == 0xBF { return "utf8" }
        if data[0] == 0xFF, data[1] == 0xFE { return "utf16le" }
        if data[0] == 0xFE, data[1] == 0xFF { return "utf16be" }
        return "none"
    }

    private static func countByte(_ byte: UInt8, in data: Data) -> Int {
        data.reduce(0) { $0 + ($1 == byte ? 1 : 0) }
    }

    private static func countSequence(_ sequence: [UInt8], in data: Data) -> Int {
        guard !sequence.isEmpty, data.count >= sequence.count else { return 0 }
        var count = 0
        var index = 0
        while index <= data.count - sequence.count {
            if sequence.enumerated().allSatisfy({ data[index + $0.offset] == $0.element }) {
                count += 1
                index += sequence.count
            } else {
                index += 1
            }
        }
        return count
    }

    private static func hexString(_ slice: some DataProtocol) -> String {
        slice.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
#endif
