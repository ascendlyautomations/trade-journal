import SwiftUI

/// Manage Room → Tags — Create Tag + editable tag list with inline section Edit/Done.
struct ManageRoomTagsView: View {
    @Bindable var viewModel: ManageRoomViewModel
    @Binding var newTagName: String
    @Binding var newTagColorKey: String
    @Binding var editingTag: RoomMemberTag?

    @Environment(\.themeColors) private var colors
    @State private var isEditingTags = false
    @State private var tagPendingDelete: RoomMemberTag?

    var body: some View {
        List {
            Section("Create Tag") {
                TextField("Tag name", text: $newTagName)
                Picker("Color", selection: $newTagColorKey) {
                    ForEach(RoomMemberTagSupport.presetColorKeys, id: \.key) { option in
                        Text(option.label).tag(option.key)
                    }
                }
                Button("Create Tag") {
                    Task {
                        await viewModel.createTag(name: newTagName, colorKey: newTagColorKey)
                        newTagName = ""
                    }
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isMutatingTag)
            }

            Section {
                ForEach(viewModel.tags) { tag in
                    tagRow(tag)
                }
            } header: {
                HStack {
                    Text("TAGS")
                    Spacer()
                    if viewModel.canManageRoom {
                        Button(isEditingTags ? "Done" : "Edit") {
                            ExperienceHaptics.play(.selection)
                            if isEditingTags {
                                isEditingTags = false
                                tagPendingDelete = nil
                            } else {
                                isEditingTags = true
                            }
                        }
                        .font(.subheadline.weight(isEditingTags ? .semibold : .regular))
                        .accessibilityIdentifier(
                            isEditingTags ? "tradeRooms.tags.done" : "tradeRooms.tags.edit"
                        )
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .experienceDashboardGroupedRows()
        .scrollContentBackground(.hidden)
        .experienceNavigationTitle("Tags")
        .refreshable { await viewModel.refreshTags() }
        .confirmationDialog(
            "Delete this tag?",
            isPresented: Binding(
                get: { tagPendingDelete != nil },
                set: { if !$0 { tagPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tag = tagPendingDelete {
                Button("Delete", role: .destructive) {
                    let target = tag
                    tagPendingDelete = nil
                    Task { await viewModel.deleteTag(target) }
                }
            }
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            if let tag = tagPendingDelete {
                Text("“\(tag.name)” will be removed from this room and unassigned from members.")
            }
        }
        .accessibilityIdentifier("tradeRooms.tags")
    }

    @ViewBuilder
    private func tagRow(_ tag: RoomMemberTag) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if isEditingTags, viewModel.canManageRoom {
                Button {
                    tagPendingDelete = tag
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(tag.name)")
            }

            if isEditingTags {
                tagLabel(tag)
            } else {
                Button {
                    editingTag = tag
                } label: {
                    tagLabel(tag)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tagLabel(_ tag: RoomMemberTag) -> some View {
        HStack {
            Circle()
                .fill(RoomMemberTagSupport.color(for: tag.colorKey, colors: colors))
                .frame(width: 10, height: 10)
            Text(tag.name)
                .experienceStyle(.body, color: colors.primaryText)
            if tag.isPreset {
                Text("Preset")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
