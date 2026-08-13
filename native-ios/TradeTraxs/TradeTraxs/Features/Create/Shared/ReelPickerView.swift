import SwiftUI

/// Bounded picker of the viewer's **unattached** clips (web: `reels.trade_id IS NULL`).
struct ReelPickerView: View {
    let reels: [Reel]
    var isLoading: Bool
    var onSelect: (Reel) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reels.isEmpty {
                ExperienceEmptyState(
                    icon: .playRectangle,
                    title: "No clips to link",
                    message: "Standalone clips without a trade can be linked here."
                )
            } else {
                List(reels) { reel in
                    Button {
                        onSelect(reel)
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .fill(colors.fillSecondary)
                                .frame(width: 56, height: 72)
                                .overlay {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundStyle(colors.accent)
                                }
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                                    ?? "Untitled clip")
                                    .experienceStyle(.headline, color: colors.primaryText)
                                    .lineLimit(2)
                                HStack(spacing: ExperienceSpacing.sm) {
                                    if let seconds = reel.durationSeconds {
                                        Text(Self.formatDuration(seconds))
                                            .experienceStyle(.caption, color: colors.secondaryText)
                                    }
                                    Text(reel.createdAt, style: .date)
                                        .experienceStyle(.caption, color: colors.tertiaryText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("create.reelPicker.\(reel.id.rawValue)")
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Link Clip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("create.reelPicker")
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
