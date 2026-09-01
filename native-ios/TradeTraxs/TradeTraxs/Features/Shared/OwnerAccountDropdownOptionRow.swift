import SwiftUI

/// List/sheet account row — not for the account filter overlay.
struct OwnerAccountDropdownOptionRow: View {
    let account: TradingAccount

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(TradingAccountDisplay.ownerDropdownLine(for: account))
            .experienceStyle(.footnote, color: colors.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(TradingAccountDisplay.ownerDropdownLine(for: account))
    }
}

/// Filter overlay row — fixed checkmark column + one composed account line.
struct OwnerAccountDropdownFilterRow: View {
    let account: TradingAccount
    let isSelected: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                } else {
                    Color.clear
                }
            }
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)

            Text(TradingAccountDisplay.ownerDropdownLine(for: account))
                .experienceStyle(.footnote, color: colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: OwnerAccountDropdownSupport.filterMenuAccountRowHeight)
        .accessibilityLabel(TradingAccountDisplay.ownerDropdownLine(for: account))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Native ``Menu`` label — composed ``Text`` so mode and masked suffix render reliably.
struct OwnerAccountDropdownMenuLabel: View {
    let account: TradingAccount
    let isSelected: Bool

    var body: some View {
        let line = TradingAccountDisplay.ownerDropdownLine(for: account)
        if isSelected {
            Label(line, systemImage: "checkmark")
        } else {
            Text(line)
        }
    }
}

/// ``Picker`` row label — composed line (may wrap in Form pickers).
struct OwnerAccountDropdownPickerLabel: View {
    let account: TradingAccount

    var body: some View {
        Text(TradingAccountDisplay.ownerDropdownLine(for: account))
    }
}
