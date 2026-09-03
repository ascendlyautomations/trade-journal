import Foundation

/// Parses broker screenshot timestamps with OCR-tolerant normalization.
nonisolated enum ScreenshotDateTimeParser {
    static func parse(_ raw: String?) -> Date? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        s = normalizeOCR(s)
        if let combined = parseDateTimeString(s) { return combined }
        if let dateOnly = parseDateOnly(s) { return dateOnly }
        return nil
    }

    static func normalizeOCR(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "•", with: ".")
            .replacingOccurrences(of: "O", with: "0") // only in numeric contexts handled below
        s = s.replacingOccurrences(of: #"(\d{2}/\d{2})\((\d{4})"#, with: "$1/$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)l(\d)"#, with: "$1/$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d{2})(\d{2}/\d{4})"#, with: "$1/$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}:\d{2})[:\.](\d{1,3})"#, with: "$1 $2.$3", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d{2}:\d{2}:\d{2})(\d{2})(AM|PM)"#, with: "$1.$2 $3", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d{2}:\d{2}:\d{2})(AM|PM)"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDateTimeString(_ raw: String) -> Date? {
        let formats = [
            "MM/dd/yyyy HH:mm:ss.SSS a",
            "MM/dd/yyyy HH:mm:ss.SS a",
            "MM/dd/yyyy HH:mm:ss.S a",
            "MM/dd/yyyy HH:mm:ss a",
            "MM/dd/yyyy HH:mm a",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        for format in formats {
            if let date = parse(raw, format: format) { return date }
        }
        if raw.contains(" ") {
            let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let datePart = String(parts[0])
                let timePart = parts.dropFirst().joined(separator: " ")
                if let date = parseDateOnly(datePart) {
                    return merge(date: date, time: timePart)
                }
            }
        }
        return nil
    }

    private static func parseDateOnly(_ raw: String) -> Date? {
        let formats = [
            "dd-MM-yyyy", "d-M-yyyy",
            "MM/dd/yyyy", "M/d/yyyy",
            "yyyy-MM-dd", "yyyy/MM/dd",
            "MMM d, yyyy", "MMM d yyyy",
        ]
        for format in formats {
            if let date = parse(raw, format: format) { return date }
        }
        return nil
    }

    private static func merge(date: Date, time: String) -> Date? {
        let timeFormats = [
            "HH:mm:ss.SSS a", "HH:mm:ss.SS a", "HH:mm:ss.S a",
            "HH:mm:ss a", "HH:mm a", "HH:mm:ss", "HH:mm",
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        let dayStart = calendar.startOfDay(for: date)
        for format in timeFormats {
            let formatter = makeFormatter(format: format)
            if let parsed = formatter.date(from: time) {
                let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: parsed)
                return calendar.date(byAdding: parts, to: dayStart)
            }
        }
        return dayStart
    }

    private static func parse(_ raw: String, format: String) -> Date? {
        let formatter = makeFormatter(format: format)
        return formatter.date(from: raw)
    }

    private static var easternTimeZone: TimeZone {
        TimeZone(identifier: "America/New_York") ?? .gmt
    }

    private static func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = format
        return formatter
    }
}
