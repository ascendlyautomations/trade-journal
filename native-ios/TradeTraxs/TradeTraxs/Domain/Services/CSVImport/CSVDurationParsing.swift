import Foundation

/// Web `parseDurationCsvValue` — duration cell → whole seconds.
nonisolated enum CSVDurationParsing {
    static func parse(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        if s.range(of: #"^\d+$"#, options: .regularExpression) != nil,
           let v = Int(s), v >= 0
        {
            return v
        }

        let compact = s.replacingOccurrences(of: " ", with: "")
        let hmsGroups = matchGroups(compact, pattern: ##"^(\d+):(\d{2}):(\d{2})$"##)
        if hmsGroups.count == 3,
           let h = Int(hmsGroups[0]), let m = Int(hmsGroups[1]), let sec = Int(hmsGroups[2])
        {
            return h * 3600 + m * 60 + sec
        }
        let msGroups = matchGroups(compact, pattern: ##"^(\d+):(\d{2})$"##)
        if msGroups.count == 2,
           let m = Int(msGroups[0]), let sec = Int(msGroups[1])
        {
            return m * 60 + sec
        }

        var total = 0.0
        var any = false
        if let h = firstCaptureDouble(in: s, pattern: #"(\d+(?:\.\d+)?)\s*h"#) {
            total += h * 3600
            any = true
        }
        if let m = firstCaptureDouble(
            in: s,
            pattern: #"(\d+(?:\.\d+)?)\s*(?:m(?![a-z])|min(?:ute)?s?)"#,
            caseInsensitive: true
        ) {
            total += m * 60
            any = true
        }
        if let sec = firstCaptureDouble(
            in: s,
            pattern: #"(\d+(?:\.\d+)?)\s*(?:s(?![a-z])|sec(?:ond)?s?)"#,
            caseInsensitive: true
        ) {
            total += sec
            any = true
        }
        guard any else { return nil }
        return max(0, Int(total.rounded()))
    }

    private static func matchGroups(_ s: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s))
        else { return [] }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: i), in: s) else { continue }
            groups.append(String(s[range]))
        }
        return groups
    }

    private static func firstCaptureDouble(
        in s: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> Double? {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: s)
        else { return nil }
        return Double(s[range])
    }
}
