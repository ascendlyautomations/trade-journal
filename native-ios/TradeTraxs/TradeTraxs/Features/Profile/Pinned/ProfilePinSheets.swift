import SwiftUI

struct ProfilePinReplaceSheet: View {
    let message: String
    let currentPins: [ProfilePinnedItem]
    let onReplace: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .listRowBackground(colors.backgroundPrimary)
                }

                Section("Pinned to Profile") {
                    ForEach(currentPins.sorted(by: { $0.position < $1.position })) { item in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text("\(item.position). \(item.preview.title)")
                                .experienceStyle(.body, color: colors.primaryText)
                                .lineLimit(2)
                            if let subtitle = item.preview.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .experienceStyle(.caption, color: colors.secondaryText)
                                    .lineLimit(1)
                            }
                            Button("Replace #\(item.position)") {
                                onReplace(item.position)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(colors.backgroundPrimary)
                        .accessibilityIdentifier("profile.pin.replace.\(item.position)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .experienceScreenBackground()
            .navigationTitle("Replace Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("profile.pin.replace.sheet")
    }
}

struct ProfileManagePinnedSheet: View {
    let items: [ProfilePinnedItem]
    let onOpen: (ProfilePinnedItem) -> Void
    let onUnpin: (ProfilePinnedItem) -> Void
    let onMoveUp: (ProfilePinnedItem) -> Void
    let onMoveDown: (ProfilePinnedItem) -> Void
    let onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    private var sorted: [ProfilePinnedItem] {
        items.sorted { $0.position < $1.position }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sorted) { item in
                    HStack(spacing: ExperienceSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.position). \(item.preview.kindLabel)")
                                .experienceStyle(.caption, color: colors.secondaryText)
                            Text(item.preview.title)
                                .experienceStyle(.body, color: colors.primaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if item.position > 1 {
                            Button {
                                onMoveUp(item)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                        if item.position < sorted.count {
                            Button {
                                onMoveDown(item)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onUnpin(item)
                        } label: {
                            Label("Unpin", systemImage: "pin.slash")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(item) }
                    .listRowBackground(colors.backgroundPrimary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .experienceScreenBackground()
            .navigationTitle("Manage Pinned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("profile.pin.manage.sheet")
    }
}
