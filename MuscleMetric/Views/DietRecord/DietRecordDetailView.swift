import SwiftUI
import CoreData

struct DietRecordDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var record: DietRecord
    
    @State private var showFoodPicker = false
    @State private var showCopiedAlert = false
    
    var entries: [DietEntry] {
        let set = record.entries as? Set<DietEntry> ?? []
        return set.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    var foods: [DietTag] {
        entries.compactMap { $0.foodTag }
    }
    
    var body: some View {
        VStack {
            List {
                Section(header: Text("基本信息")) {
                    TextField("标题", text: Binding($record.title, replacingNilWith: ""))
                    DatePicker("日期", selection: Binding($record.date, replacingNilWith: Date()), displayedComponents: .date)
                }
                
                Section(header: Text("已选食物")) {
                    ForEach(entries) { entry in
                        if let food = entry.foodTag {
                            HStack {
                                Text(food.name ?? "未知")
                                Spacer()
                                Text("\(Int(food.calories)) kcal")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteEntry)
                    
                    Button(action: { showFoodPicker = true }) {
                        Label("添加食物", systemImage: "plus")
                    }
                }
            }
            
            DietSummaryView(foods: foods)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
        }
        .navigationTitle("饮食记录详情")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("记录详情已复制到剪切板")
        }
        .sheet(isPresented: $showFoodPicker) {
            FoodPickerView(selectedFoods: Binding(
                get: { [] }, // Dummy getter
                set: { newFoods in
                    // When picker adds foods, we create entries
                    for food in newFoods {
                        addEntry(food: food)
                    }
                }
            ))
        }
    }
    
    private func addEntry(food: DietTag) {
        let newEntry = DietEntry(context: viewContext)
        newEntry.id = UUID()
        newEntry.foodTag = food
        newEntry.record = record
        newEntry.orderIndex = Int32(entries.count)
        
        saveContext()
    }
    
    private func deleteEntry(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
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
        text += "日期: \(dateFormatter.string(from: record.date ?? Date()))\n"
        text += "标题: \(record.title ?? "")\n"
        text += "----------------\n"
        
        var totalCal = 0.0
        var totalP = 0.0
        var totalC = 0.0
        var totalF = 0.0
        
        for food in foods {
            text += "- \(food.name ?? ""): \(Int(food.calories)) kcal (P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fat)))\n"
            totalCal += food.calories
            totalP += food.protein
            totalC += food.carbs
            totalF += food.fat
        }
        
        text += "----------------\n"
        text += "当日概要:\n"
        text += "总热量: \(Int(totalCal)) kcal\n"
        text += "总蛋白质: \(Int(totalP)) g\n"
        text += "总碳水: \(Int(totalC)) g\n"
        text += "总脂肪: \(Int(totalF)) g\n"
        
        UIPasteboard.general.string = text
        showCopiedAlert = true
    }
}

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith nilProxy: Value) {
        self.init(
            get: { source.wrappedValue ?? nilProxy },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()
