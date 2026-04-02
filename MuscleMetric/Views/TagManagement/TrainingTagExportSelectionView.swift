import SwiftUI
import CoreData

struct TrainingTagExportSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        entity: TrainingTag.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \TrainingTag.level, ascending: true),
            NSSortDescriptor(keyPath: \TrainingTag.category, ascending: true),
            NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)
        ],
        animation: .default
    )
    private var trainingTags: FetchedResults<TrainingTag>

    @State private var selectedIds: Set<UUID> = []
    @State private var searchText: String = ""

    let onConfirm: (_ selectedIds: Set<UUID>?) -> Void

    private var selectableTags: [TrainingTag] {
        trainingTags.filter { $0.id != nil }
    }

    private var allIds: Set<UUID> {
        Set(selectableTags.compactMap(\.id))
    }

    private var filteredTags: [TrainingTag] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return selectableTags }
        return selectableTags.filter { tag in
            let path = trainingTagPath(tag)
            return path.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredTags) { tag in
                    Button(action: {
                        toggle(tagId: tag.id)
                    }) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trainingTagPath(tag))
                                    .foregroundColor(.primary)
                                if tag.level == 2, let category = tag.category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("分类：\(category)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let id = tag.id, selectedIds.contains(id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择力训标签")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索（支持门店/动作/重量）")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("全不选") {
                        selectedIds = []
                    }
                    Button("全选") {
                        selectedIds = allIds
                    }
                    Button("导出") {
                        let selected: Set<UUID>? = selectedIds == allIds ? nil : selectedIds
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(allIds.isEmpty || selectedIds.isEmpty)
                }
            }
            .onAppear {
                normalizeIdsIfNeeded()
                selectedIds = allIds
            }
        }
    }

    private func toggle(tagId: UUID?) {
        guard let tagId else { return }
        if selectedIds.contains(tagId) {
            selectedIds.remove(tagId)
        } else {
            selectedIds.insert(tagId)
        }
    }

    private func trainingTagPath(_ tag: TrainingTag) -> String {
        var parts: [String] = []
        var current: TrainingTag? = tag
        var visited: Set<NSManagedObjectID> = []
        while let t = current {
            if visited.contains(t.objectID) { break }
            visited.insert(t.objectID)
            let name = (t.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                parts.append(name)
            }
            current = t.parent
        }
        if parts.isEmpty { return "未命名标签" }
        return parts.reversed().joined(separator: " / ")
    }

    private func normalizeIdsIfNeeded() {
        let tagsNeedingId = trainingTags.filter { $0.id == nil }
        guard !tagsNeedingId.isEmpty else { return }
        for tag in tagsNeedingId {
            tag.id = UUID()
        }
        do {
            try viewContext.save()
        } catch {
        }
    }
}

