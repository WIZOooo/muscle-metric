import SwiftUI
import CoreData

struct TrainingRecordDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var record: TrainingRecord
    @State private var showCopiedAlert = false
    @State private var showAddEntrySheet = false
    @State private var editingEntry: TrainingEntry?
    
    // State for toggling categories
    @State private var expandedCategories: Set<String> = []
    @State private var expandedActions: Set<UUID> = []
    
    // Shortcut sheet state
    @State private var showCreateActionSheet = false
    @State private var newActionName = ""
    @State private var newActionCategory = ""
    @State private var newActionInitialWeight = ""
    
    // Quick Add Weight sheet
    struct QuickAddContext: Identifiable {
        let id = UUID()
        let action: TrainingTag
    }
    @State private var quickAddContext: QuickAddContext?
    
    // Grouping Logic
    struct GroupedCategory: Identifiable {
        let id: String
        let name: String
        var actions: [GroupedAction]
    }
    
    struct GroupedAction: Identifiable {
        let id: UUID
        let tag: TrainingTag
        var entries: [TrainingEntry]
    }
    
    var groupedData: [GroupedCategory] {
        guard let entries = record.entries as? Set<TrainingEntry> else { return [] }
        
        // 1. Group by Category
        let entriesByCategory = Dictionary(grouping: entries) { entry in
            entry.actionTag?.category ?? "未分类"
        }
        
        var categories: [GroupedCategory] = []
        
        for (categoryName, catEntries) in entriesByCategory {
            // 2. Group by Action within Category
            let entriesByAction = Dictionary(grouping: catEntries) { entry in
                entry.actionTag
            }
            
            var actions: [GroupedAction] = []
            for (actionTag, actEntries) in entriesByAction {
                if let tag = actionTag, let id = tag.id {
                    let sortedEntries = actEntries.sorted { $0.orderIndex < $1.orderIndex }
                    actions.append(GroupedAction(id: id, tag: tag, entries: sortedEntries))
                }
            }
            
            // Sort actions by name
            actions.sort { ($0.tag.name ?? "") < ($1.tag.name ?? "") }
            
            categories.append(GroupedCategory(id: categoryName, name: categoryName, actions: actions))
        }
        
        // Sort categories (put "未分类" at the end if desired, or just alphabetical)
        categories.sort { $0.name < $1.name }
        
        return categories
    }
    
    var body: some View {
        List {
            Section(header: Text("基本信息")) {
                HStack {
                    Text("标题")
                    Spacer()
                    TextField("标题", text: Binding(
                        get: { record.title ?? "" },
                        set: { 
                            record.title = $0
                            saveContext()
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("时间")
                    Spacer()
                    Text("\(record.timestamp ?? Date(), formatter: itemFormatter)")
                }
                if let gym = record.gymTag {
                    HStack {
                        Text("门店")
                        Spacer()
                        Text(gym.name ?? "")
                    }
                }
            }
            
            Section(header: Text("训练内容")) {
                if groupedData.isEmpty {
                    Text("无记录")
                } else {
                    ForEach(groupedData) { category in
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
                            ForEach(category.actions) { actionGroup in
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedActions.contains(actionGroup.id) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedActions.insert(actionGroup.id)
                                            } else {
                                                expandedActions.remove(actionGroup.id)
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(actionGroup.entries) { entry in
                                        Button(action: { editingEntry = entry }) {
                                            HStack {
                                                Text(entry.weightTag?.name ?? "未知重量")
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                Image(systemName: "pencil")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .onDelete { indexSet in
                                        deleteEntries(in: actionGroup, at: indexSet)
                                    }
                                } label: {
                                    HStack {
                                        // Link to TrainingTagListView (Level 3 - Weights)
                                        NavigationLink(destination: TrainingTagListView(parentTag: actionGroup.tag)) {
                                            Text(actionGroup.tag.name ?? "未知动作")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                        }
                                        Spacer()
                                        // Quick add button
                                        Button(action: {
                                            quickAddContext = QuickAddContext(action: actionGroup.tag)
                                        }) {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        } label: {
                            Text(category.name)
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                if let gym = record.gymTag {
                    HStack {
                        Button(action: { showAddEntrySheet = true }) {
                            Label("添加动作", systemImage: "plus")
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("记录详情")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateActionSheet = true }) {
                    Image(systemName: "tag")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
            }
        }
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("记录详情已复制到剪切板")
        }
        .sheet(isPresented: $showAddEntrySheet) {
            if let gym = record.gymTag {
                AddEntrySheet(gym: gym) { action, weight in
                    addEntry(action: action, weight: weight)
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            if let gym = record.gymTag {
                EditEntrySheet(gym: gym, entry: entry)
            }
        }
        .sheet(isPresented: $showCreateActionSheet) {
            NavigationView {
                Form {
                    Section {
                        TextField("动作名称", text: $newActionName)
                            .frame(minHeight: 44)
                        TextField("分类 (如: 练胸, 练背)", text: $newActionCategory)
                            .frame(minHeight: 44)
                        TextField("初始重量 (可选, 如: 20kg)", text: $newActionInitialWeight)
                            .frame(minHeight: 44)
                    } header: {
                        Text("动作信息")
                    }
                }
                .navigationTitle("新建动作")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showCreateActionSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            createNewAction()
                            showCreateActionSheet = false
                        }
                        .disabled(newActionName.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $quickAddContext) { context in
            if let gym = context.action.parent ?? record.gymTag {
                AddEntrySheet(gym: gym, initialAction: context.action) { selectedAction, selectedWeight in
                    addEntry(action: selectedAction, weight: selectedWeight)
                    quickAddContext = nil
                }
            } else {
                Text("错误：无法获取门店信息")
            }
        }
        .onAppear {
            // Expand all by default
            let categories = groupedData
            for cat in categories {
                expandedCategories.insert(cat.id)
                for action in cat.actions {
                    expandedActions.insert(action.id)
                }
            }
        }
    }
    
    private func createNewAction() {
        guard let gym = record.gymTag else { return }
        
        let newTag = TrainingTag(context: viewContext)
        newTag.id = UUID()
        newTag.name = newActionName
        newTag.category = newActionCategory
        newTag.level = 2
        newTag.parent = gym
        
        // If initial weight provided, create Level 3 tag
        if !newActionInitialWeight.isEmpty {
            let weightTag = TrainingTag(context: viewContext)
            weightTag.id = UUID()
            weightTag.name = newActionInitialWeight
            weightTag.level = 3
            weightTag.parent = newTag
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving new tag: \(error)")
        }
        
        newActionName = ""
        newActionCategory = ""
        newActionInitialWeight = ""
    }
    
    private func addEntry(action: TrainingTag, weight: TrainingTag) {
        let newEntry = TrainingEntry(context: viewContext)
        newEntry.id = UUID()
        newEntry.actionTag = action
        newEntry.weightTag = weight
        newEntry.record = record
        
        // Set order index to be last
        let currentCount = (record.entries?.count ?? 0)
        newEntry.orderIndex = Int32(currentCount)
        
        saveContext()
    }
    
    private func deleteEntries(in group: GroupedAction, at offsets: IndexSet) {
        for index in offsets {
            let entry = group.entries[index]
            viewContext.delete(entry)
        }
        saveContext()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    private func copyToClipboard() {
        var text = ""
        text += "标题: \(record.title ?? "")\n"
        text += "时间: \(itemFormatter.string(from: record.timestamp ?? Date()))\n"
        if let gym = record.gymTag {
            text += "门店: \(gym.name ?? "")\n"
        }
        text += "----------------\n"
        
        for category in groupedData {
            text += "【\(category.name)】\n"
            for action in category.actions {
                text += "- \(action.tag.name ?? ""):\n"
                for entry in action.entries {
                    text += "  • \(entry.weightTag?.name ?? "")\n"
                }
            }
        }
        
        UIPasteboard.general.string = text
        showCopiedAlert = true
    }
}



// ... existing EditEntrySheet and formatter ...
struct EditEntrySheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    var gym: TrainingTag
    @ObservedObject var entry: TrainingEntry
    
    @State private var selectedAction: TrainingTag?
    @State private var selectedWeight: TrainingTag?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("选择动作")) {
                    ActionPicker(parent: gym, selection: $selectedAction)
                }
                
                // Show weight picker if action is selected (either new selection or existing one)
                if selectedAction != nil {
                    Section(header: Text("选择重量")) {
                        // We need a binding that updates when selectedAction changes context
                        WeightPicker(parent: selectedAction!, selection: $selectedWeight)
                    }
                }
            }
            .navigationTitle("编辑动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let action = selectedAction, let weight = selectedWeight {
                            entry.actionTag = action
                            entry.weightTag = weight
                            try? viewContext.save()
                            dismiss()
                        }
                    }
                    .disabled(selectedAction == nil || selectedWeight == nil)
                }
            }
            .onAppear {
                // Initialize selection from existing entry
                selectedAction = entry.actionTag
                selectedWeight = entry.weightTag
            }
            .onChange(of: selectedAction) { newValue in
                // If action changes, clear weight unless it's the initial load
                if newValue != entry.actionTag {
                    selectedWeight = nil
                }
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()
