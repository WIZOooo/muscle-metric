import SwiftUI
import CoreData

struct DietTagExportSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietTag.name, ascending: true)],
        animation: .default
    )
    private var dietTags: FetchedResults<DietTag>

    @State private var selectedIds: Set<UUID> = []
    @State private var searchText: String = ""

    let onConfirm: (_ selectedIds: Set<UUID>?) -> Void

    private var selectableTags: [DietTag] {
        dietTags.filter { $0.id != nil }
    }

    private var allIds: Set<UUID> {
        Set(selectableTags.compactMap(\.id))
    }

    private var filteredTags: [DietTag] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return selectableTags }
        return selectableTags.filter { tag in
            (tag.name ?? "").localizedCaseInsensitiveContains(keyword)
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
                                Text(tag.name ?? "未知食物")
                                    .foregroundColor(.primary)
                                Text("热量 \(Int(tag.calories)) / 蛋白 \(Int(tag.protein)) / 碳水 \(Int(tag.carbs)) / 脂肪 \(Int(tag.fat))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
            .navigationTitle("选择饮食标签")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索")
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

    private func normalizeIdsIfNeeded() {
        let tagsNeedingId = dietTags.filter { $0.id == nil }
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

