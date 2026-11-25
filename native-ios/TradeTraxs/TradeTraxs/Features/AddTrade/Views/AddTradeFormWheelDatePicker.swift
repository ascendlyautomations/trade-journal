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

/// Compact bottom sheet with a centered hour/minute wheel (Trading Rules planned times, etc.).
struct AddTradeWheelTimePickerSheet: View {
    let title: String
    @Binding var selection: Date
    var onClear: (() -> Void)? = nil
    let onDone: () -> Void

    @Environment(\.themeColors) private var colors

    /// Wheel (~216pt) + header; avoids medium/large detents that feel full-screen.
    static let presentationHeight: CGFloat = 296

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            sheetHeader
            DatePicker(
                "",
                selection: $selection,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.timeZone, AddTradeWheelTimePickerSupport.easternCalendar.timeZone)
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, ExperienceSpacing.xs)
        .experienceSheetChrome(
            detents: [.height(Self.presentationHeight)],
            dragIndicator: .visible,
            keyboardDoneToolbar: false
        )
    }

    private var sheetHeader: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if let onClear {
                Button("Clear", action: onClear)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
            } else {
                Color.clear
                    .frame(width: 52, height: 1)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: ExperienceSpacing.xs)
            Button("Done", action: onDone)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
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