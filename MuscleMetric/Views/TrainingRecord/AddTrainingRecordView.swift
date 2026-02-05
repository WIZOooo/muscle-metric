import SwiftUI
import CoreData

struct AddTrainingRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var timestamp = Date()
    @State private var selectedGym: TrainingTag?
    
    @State private var showCopiedAlert = false
    
    // Temporary struct to hold selected entries before saving
    struct TempEntry: Identifiable {
        let id = UUID()
        var action: TrainingTag
        var weight: TrainingTag
    }
    @State private var tempEntries: [TempEntry] = []
    
    @State private var showAddEntrySheet = false
    
    // Fetch all gyms (level 1)
    @FetchRequest(
        entity: TrainingTag.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)],
        predicate: NSPredicate(format: "level == 1")
    ) private var gyms: FetchedResults<TrainingTag>
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("标题", text: $title)
                    DatePicker("时间", selection: $timestamp)
                }
                
                Section(header: Text("健身门店")) {
                    if tempEntries.isEmpty {
                        Picker("选择门店", selection: $selectedGym) {
                            Text("请选择").tag(nil as TrainingTag?)
                            ForEach(gyms) { gym in
                                Text(gym.name ?? "").tag(gym as TrainingTag?)
                            }
                        }
                    } else {
                        // Locked if entries exist
                        if let gym = selectedGym {
                            Text(gym.name ?? "未知门店")
                                .foregroundColor(.primary)
                            Text("（已锁定：如需更改请先删除下方所有动作）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("训练动作")) {
                    ForEach(tempEntries) { entry in
                        HStack {
                            Text(entry.action.name ?? "")
                            Spacer()
                            Text(entry.weight.name ?? "")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        tempEntries.remove(atOffsets: indexSet)
                        if tempEntries.isEmpty {
                            // Unlock gym selection if needed? 
                            // Actually user might want to keep it, but it's editable now.
                        }
                    }
                    
                    if let gym = selectedGym {
                        Button(action: { showAddEntrySheet = true }) {
                            Label("添加动作", systemImage: "plus")
                        }
                    } else {
                        Text("请先选择健身门店")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("复制到剪切板") {
                        copyToClipboard()
                    }
                }
            }
            .navigationTitle("新建力训记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRecord()
                        dismiss()
                    }
                    .disabled(selectedGym == nil || tempEntries.isEmpty)
                }
            }
            .sheet(isPresented: $showAddEntrySheet) {
                if let gym = selectedGym {
                    AddEntrySheet(gym: gym) { action, weight in
                        tempEntries.append(TempEntry(action: action, weight: weight))
                    }
                }
            }
            .alert("已复制", isPresented: $showCopiedAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text("记录内容已复制到剪切板")
            }
        }
    }
    
    private func saveRecord() {
        guard let gym = selectedGym else { return }
        
        let newRecord = TrainingRecord(context: viewContext)
        newRecord.id = UUID()
        newRecord.timestamp = timestamp
        newRecord.title = title.isEmpty ? "训练记录" : title
        newRecord.gymTag = gym
        
        for (index, entry) in tempEntries.enumerated() {
            let newEntry = TrainingEntry(context: viewContext)
            newEntry.id = UUID()
            newEntry.orderIndex = Int32(index)
            newEntry.actionTag = entry.action
            newEntry.weightTag = entry.weight
            newEntry.record = newRecord
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving record: \(error)")
        }
    }
    
    private func copyToClipboard() {
        var text = ""
        text += "标题: \(title.isEmpty ? "训练记录" : title)\n"
        text += "时间: \(itemFormatter.string(from: timestamp))\n"
        if let gym = selectedGym {
            text += "门店: \(gym.name ?? "")\n"
        }
        text += "----------------\n"
        for entry in tempEntries {
            text += "- \(entry.action.name ?? ""): \(entry.weight.name ?? "")\n"
        }
        UIPasteboard.general.string = text
        showCopiedAlert = true
    }
}

struct AddEntrySheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    var gym: TrainingTag
    var initialAction: TrainingTag? = nil
    var onSave: (TrainingTag, TrainingTag) -> Void
    
    @State private var selectedAction: TrainingTag?
    @State private var selectedWeight: TrainingTag?
    @State private var lastRecordInfo: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("选择动作")) {
                    ActionPicker(parent: gym, selection: $selectedAction)
                }
                
                if let action = selectedAction {
                    Section(header: Text("选择重量"), footer: Text(lastRecordInfo).font(.caption).foregroundColor(.secondary)) {
                        WeightPicker(parent: action, selection: $selectedWeight)
                    }
                }
            }
            .navigationTitle("添加动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        if let action = selectedAction, let weight = selectedWeight {
                            onSave(action, weight)
                            dismiss()
                        }
                    }
                    .disabled(selectedAction == nil || selectedWeight == nil)
                }
            }
        }
        .onAppear {
            if let initial = initialAction, selectedAction == nil {
                selectedAction = initial
            }
            updateLastRecordInfo()
        }
        .onChange(of: selectedAction) { _ in
            updateLastRecordInfo()
        }
    }
    
    private func updateLastRecordInfo() {
        guard let action = selectedAction else {
            lastRecordInfo = ""
            return
        }
        
        let request = NSFetchRequest<TrainingRecord>(entityName: "TrainingRecord")
        request.predicate = NSPredicate(format: "gymTag == %@ AND SUBQUERY(entries, $e, $e.actionTag == %@).@count > 0", gym, action)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TrainingRecord.timestamp, ascending: false)]
        request.fetchLimit = 1
        
        do {
            let records = try viewContext.fetch(request)
            if let lastRecord = records.first, let entries = lastRecord.entries as? Set<TrainingEntry> {
                // Filter entries for this action
                let actionEntries = entries.filter { $0.actionTag == action }
                
                // Find max weight
                let maxEntry = actionEntries.max { a, b in
                    let weightA = parseWeight(a.weightTag?.name)
                    let weightB = parseWeight(b.weightTag?.name)
                    return weightA < weightB
                }
                
                if let maxEntry = maxEntry, let weightName = maxEntry.weightTag?.name, let date = lastRecord.timestamp {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy/MM/dd"
                    let dateString = formatter.string(from: date)
                    lastRecordInfo = "\(dateString) 最大重量为\(weightName)"
                } else {
                    lastRecordInfo = ""
                }
            } else {
                lastRecordInfo = ""
            }
        } catch {
            print("Error fetching last record: \(error)")
            lastRecordInfo = ""
        }
    }
    
    private func parseWeight(_ name: String?) -> Double {
        guard let name = name else { return 0 }
        let numberString = name.filter { "0123456789.".contains($0) }
        return Double(numberString) ?? 0
    }
}

struct ActionSelectionListView: View {
    let actions: [TrainingTag]
    @Binding var selection: TrainingTag?
    @Environment(\.dismiss) private var dismiss
    
    @State private var expandedCategories: Set<String> = []

    var groupedActions: [String: [TrainingTag]] {
        Dictionary(grouping: actions) { $0.category ?? "未分类" }
    }
    
    var sortedCategories: [String] {
        groupedActions.keys.sorted()
    }
    
    var body: some View {
        List {
            ForEach(sortedCategories, id: \.self) { category in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCategories.insert(category)
                            } else {
                                expandedCategories.remove(category)
                            }
                        }
                    ),
                    content: {
                        ForEach(groupedActions[category] ?? []) { action in
                            Button(action: {
                                selection = action
                                dismiss()
                            }) {
                                HStack {
                                    Text(action.name ?? "")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selection == action {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    },
                    label: {
                        Text(category)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                )
            }
        }
        .navigationTitle("选择动作")
    }
}

struct ActionPicker: View {
    var parent: TrainingTag
    @Binding var selection: TrainingTag?
    
    @FetchRequest var actions: FetchedResults<TrainingTag>
    
    init(parent: TrainingTag, selection: Binding<TrainingTag?>) {
        self.parent = parent
        self._selection = selection
        self._actions = FetchRequest(
            entity: TrainingTag.entity(),
            sortDescriptors: [
                NSSortDescriptor(keyPath: \TrainingTag.category, ascending: true),
                NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)
            ],
            predicate: NSPredicate(format: "parent == %@", parent)
        )
    }
    
    var body: some View {
        NavigationLink(destination: ActionSelectionListView(actions: Array(actions), selection: $selection)) {
            HStack {
                Text("动作")
                Spacer()
                if let selected = selection {
                    Text(selected.name ?? "")
                        .foregroundColor(.primary)
                } else {
                    Text("请选择")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct WeightPicker: View {
    var parent: TrainingTag
    @Binding var selection: TrainingTag?
    
    @FetchRequest var weights: FetchedResults<TrainingTag>
    
    init(parent: TrainingTag, selection: Binding<TrainingTag?>) {
        self.parent = parent
        self._selection = selection
        self._weights = FetchRequest(
            entity: TrainingTag.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)],
            predicate: NSPredicate(format: "parent == %@", parent)
        )
    }
    
    var body: some View {
        Picker("重量", selection: $selection) {
            Text("请选择").tag(nil as TrainingTag?)
            ForEach(weights) { weight in
                Text(weight.name ?? "").tag(weight as TrainingTag?)
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
