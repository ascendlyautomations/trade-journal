import SwiftUI

/// Scroll-wheel timing controls shared by Add Trade and Trading Rules.
enum AddTradeWheelTimePickerSupport {
    /// Trading rules planned hours are interpreted in US Eastern (matches compliance copy).
    static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    static func clockString(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func minutes(fromClock raw: String) -> Int? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour >= 0, hour < 24, minute >= 0, minute < 60
        else { return nil }
        return hour * 60 + minute
    }

    static func date(forMinutes minutes: Int, calendar: Calendar = easternCalendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: today) ?? today
    }

    static func shortTimeLabel(minutes: Int, calendar: Calendar = easternCalendar) -> String {
        let date = date(forMinutes: minutes, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Inline wheel date/time rows in the Add Trade `Form` (Entry / Exit).
struct AddTradeFormWheelDatePicker: View {
    let title: String
    @Binding var selection: Date
    var displayedComponents: DatePicker.Components = [.date, .hourAndMinute]

    var body: some View {
        DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
    }
}