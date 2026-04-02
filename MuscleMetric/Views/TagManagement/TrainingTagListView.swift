import SwiftUI
import CoreData

struct TrainingTagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var parentTag: TrainingTag?
    
    @FetchRequest var tags: FetchedResults<TrainingTag>
    
    @State private var showAddAlert = false
    @State private var newTagName = ""
    @State private var newTagCategory = ""
    
    @State private var editingTag: TrainingTag?
    @State private var showDuplicatedAlert = false
    @State private var duplicatedActionName = ""
    
    // State for toggling categories (only used when currentLevel == 2)
    @State private var expandedCategories: Set<String> = []
    
    init(parentTag: TrainingTag? = nil) {
        self.parentTag = parentTag
        let predicate: NSPredicate
        if let parent = parentTag {
            predicate = NSPredicate(format: "parent == %@", parent)
        } else {
            predicate = NSPredicate(format: "level == 1") // Root level (Gyms)
        }
        
        _tags = FetchRequest(
            entity: TrainingTag.entity(),
            sortDescriptors: [
                NSSortDescriptor(keyPath: \TrainingTag.category, ascending: true),
                NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)
            ],
            predicate: predicate
        )
    }
    
    var currentLevel: Int16 {
        if let parent = parentTag {
            return parent.level + 1
        }
        return 1
    }
    
    var navigationTitle: String {
        switch currentLevel {
        case 1: return "健身门店 (一级)"
        case 2: return "器械/动作 (二级)"
        case 3: return "重量 (三级)"
        default: return "标签"
        }
    }
    
    // Grouping Logic for Level 2 (Actions)
    struct GroupedCategory: Identifiable {
        let id: String
        let name: String
        var tags: [TrainingTag]
    }
    
    var groupedTags: [GroupedCategory] {
        if currentLevel != 2 { return [] }
        
        let grouped = Dictionary(grouping: tags) { tag in
            tag.category ?? "未分类"
        }
        
        let categories = grouped.map { (key, value) in
            GroupedCategory(id: key, name: key, tags: value.sorted { ($0.name ?? "") < ($1.name ?? "") })
        }.sorted { $0.name < $1.name }
        
        return categories
    }
    
    var body: some View {
        List {
            if currentLevel == 2 {
                // Grouped View for Actions
                ForEach(groupedTags) { category in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedCategories.contains(category.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedCategories.insert(category.id)
                                } else {
                                    expandedCategories.remove(category.id)
                                }
                            }
                        )
                    ) {
                        ForEach(category.tags) { tag in
                            NavigationLink(destination: TrainingTagListView(parentTag: tag)) {
                                VStack(alignment: .leading) {
                                    Text(tag.name ?? "未命名")
                                    if let cat = tag.category, !cat.isEmpty {
                                        Text(cat)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("复制") {
                                    duplicateAction(from: tag)
                                }
                                Button("编辑") {
                                    editingTag = tag
                                }
                                Button("删除", role: .destructive) {
                                    viewContext.delete(tag)
                                    try? viewContext.save()
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewContext.delete(tag)
                                    try? viewContext.save()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    duplicateAction(from: tag)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.gray)
                                Button {
                                    editingTag = tag
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } label: {
                        Text(category.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            } else {
                // Standard List for Level 1 and Level 3
                ForEach(tags) { tag in
                    if tag.level < 3 {
                        NavigationLink(destination: TrainingTagListView(parentTag: tag)) {
                            Text(tag.name ?? "未命名")
                        }
                        .contextMenu {
                            Button("编辑") {
                                editingTag = tag
                            }
                            Button("删除", role: .destructive) {
                                viewContext.delete(tag)
                                try? viewContext.save()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewContext.delete(tag)
                                try? viewContext.save()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editingTag = tag
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    } else {
                        // Level 3 (Weights)
                        Text(tag.name ?? "未命名")
                            .contextMenu {
                                Button("编辑") {
                                    editingTag = tag
                                }
                                Button("删除", role: .destructive) {
                                    viewContext.delete(tag)
                                    try? viewContext.save()
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewContext.delete(tag)
                                    try? viewContext.save()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingTag = tag
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .navigationTitle(parentTag?.name ?? "力训标签")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddAlert = true }) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert("已创建副本", isPresented: $showDuplicatedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("已复制为「\(duplicatedActionName)」")
        }
        // Add Sheet
        .sheet(isPresented: $showAddAlert) {
            NavigationView {
                Form {
                    TextField("标签名称", text: $newTagName)
                    if currentLevel == 2 {
                        TextField("分类 (如: 练胸, 练背)", text: $newTagCategory)
                    }
                }
                .navigationTitle("新建 \(navigationTitle)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showAddAlert = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            addItem()
                            showAddAlert = false
                            newTagName = ""
                            newTagCategory = ""
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // Edit Sheet
        .sheet(item: $editingTag) { tag in
            EditTagView(tag: tag, currentLevel: currentLevel)
        }
        .onAppear {
            if currentLevel == 2 {
                // Expand all categories by default
                let categories = groupedTags
                for cat in categories {
                    expandedCategories.insert(cat.id)
                }
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newTag = TrainingTag(context: viewContext)
            newTag.id = UUID()
            newTag.name = newTagName
            newTag.level = currentLevel
            newTag.parent = parentTag
            if currentLevel == 2 {
                newTag.category = newTagCategory
            }
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { tags[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func duplicateAction(from source: TrainingTag) {
        guard source.level == 2 else { return }
        
        let originalName = source.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = (originalName?.isEmpty == false ? originalName! : "未命名") + "副本"
        
        let existingNames = Set(tags.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) })
        var candidateName = baseName
        var suffix = 2
        while existingNames.contains(candidateName) {
            candidateName = "\(baseName)\(suffix)"
            suffix += 1
        }
        
        let newAction = TrainingTag(context: viewContext)
        newAction.id = UUID()
        newAction.name = candidateName
        newAction.category = source.category
        newAction.level = 2
        newAction.parent = source.parent
        
        let children = (source.children as? Set<TrainingTag> ?? [])
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        
        for child in children {
            guard child.level == 3 else { continue }
            let newWeight = TrainingTag(context: viewContext)
            newWeight.id = UUID()
            newWeight.name = child.name
            newWeight.level = 3
            newWeight.parent = newAction
        }
        
        do {
            try viewContext.save()
            duplicatedActionName = candidateName
            showDuplicatedAlert = true
        } catch {
            print("Error duplicating action tag: \(error)")
        }
    }
}

struct EditTagView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var tag: TrainingTag
    var currentLevel: Int16
    
    @State private var tagName: String = ""
    @State private var tagCategory: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                TextField("标签名称", text: $tagName)
                if currentLevel == 2 {
                    TextField("分类 (如: 练胸, 练背)", text: $tagCategory)
                }
            }
            .navigationTitle("编辑标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        tag.name = tagName
                        if currentLevel == 2 {
                            tag.category = tagCategory
                        }
                        try? viewContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                tagName = tag.name ?? ""
                tagCategory = tag.category ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}
