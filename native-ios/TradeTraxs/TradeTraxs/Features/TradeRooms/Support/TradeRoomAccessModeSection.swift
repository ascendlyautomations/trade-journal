import SwiftUI

/// Shared access picker for Create + Edit Trade Room — Public vs Request to Join.
struct TradeRoomAccessModeSection: View {
    @Binding var accessMode: TradeRoomAccessMode
    var preservesLegacyPrivate: Bool
    var showsModeSummaries: Bool = true
    var accessibilityRootID: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Picker("Room Access", selection: $accessMode) {
            ForEach(TradeRoomAccessMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .accessibilityIdentifier("\(accessibilityRootID).accessMode")

        if showsModeSummaries {
            Text(accessMode.summary)
                .font(.footnote)
                .foregroundStyle(colors.secondaryText)
        }

        if preservesLegacyPrivate, accessMode == .requestToJoin {
            Text(
                "This room uses a legacy private setting and stays hidden from discovery until you switch it to Public."
            )
            .font(.footnote)
            .foregroundStyle(colors.secondaryText)
        }
    }
}