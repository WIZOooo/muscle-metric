import SwiftUI
import CoreData

struct AddDietRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var date = Date()
    @State private var selectedFoods: [DietTag] = []
    @State private var showFoodPicker = false
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("基本信息")) {
                        TextField("标题", text: $title)
                            .onAppear {
                                if title.isEmpty {
                                    title = dateFormatter.string(from: date)
                                }
                            }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
                    
                    Section(header: Text("已选食物")) {
                        ForEach(selectedFoods) { food in
                            HStack {
                                Text(food.name ?? "未知")
                                Spacer()
                                Text("\(Int(food.calories)) kcal")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            selectedFoods.remove(atOffsets: indexSet)
                        }
                        
                        Button(action: { showFoodPicker = true }) {
                            Label("添加食物", systemImage: "plus")
                        }
                    }
                }
                
                DietSummaryView(foods: selectedFoods)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
            }
            .navigationTitle("新建饮食记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRecord()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showFoodPicker) {
                FoodPickerView(selectedFoods: $selectedFoods)
            }
        }
    }
    
    private func saveRecord() {
        let newRecord = DietRecord(context: viewContext)
        newRecord.id = UUID()
        newRecord.date = date
        newRecord.title = title.isEmpty ? dateFormatter.string(from: date) : title
        
        for (index, food) in selectedFoods.enumerated() {
            let entry = DietEntry(context: viewContext)
            entry.id = UUID()
            entry.orderIndex = Int32(index)
            entry.foodTag = food
            entry.record = newRecord
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving diet record: \(error)")
        }
    }
}

struct DietSummaryView: View {
    var foods: [DietTag]
    
    var totalCalories: Double { foods.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { foods.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { foods.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { foods.reduce(0) { $0 + $1.fat } }
    
    var body: some View {
        VStack(spacing: 10) {
            Text("当日概要")
                .font(.headline)
            HStack {
                SummaryItem(title: "热量", value: totalCalories, unit: "kcal")
                Divider()
                SummaryItem(title: "蛋白质", value: totalProtein, unit: "g")
                Divider()
                SummaryItem(title: "碳水", value: totalCarbs, unit: "g")
                Divider()
                SummaryItem(title: "脂肪", value: totalFat, unit: "g")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SummaryItem: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Int(value))")
                .font(.title3)
                .bold()
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFoods: [DietTag]
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietTag.name, ascending: true)],
        animation: .default)
    private var allFoods: FetchedResults<DietTag>
    
    var body: some View {
        NavigationView {
            List {
                ForEach(allFoods) { food in
                    Button(action: {
                        selectedFoods.append(food)
                        dismiss()
                    }) {
                        HStack {
                            Text(food.name ?? "未知")
                                .foregroundColor(.primary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(Int(food.calories)) kcal")
                                Text("P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fat))")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("选择食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()
