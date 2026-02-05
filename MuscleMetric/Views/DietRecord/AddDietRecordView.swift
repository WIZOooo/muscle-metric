import SwiftUI
import CoreData
import UIKit

struct SelectedFoodItem: Identifiable {
    let id = UUID()
    let food: DietTag
    var portion: Double
}

struct AddDietRecordView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var date = Date()
    @State private var selectedFoods: [SelectedFoodItem] = []
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
                        ForEach(selectedFoods) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.food.name ?? "未知")
                                    Text("份数: \(String(format: "%.1f", item.portion))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(item.food.calories * item.portion)) kcal")
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
        
        for (index, item) in selectedFoods.enumerated() {
            let entry = DietEntry(context: viewContext)
            entry.id = UUID()
            entry.orderIndex = Int32(index)
            entry.foodTag = item.food
            entry.portion = item.portion
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
    var foods: [SelectedFoodItem]
    var bmr: Double? = nil
    var activeEnergy: Double? = nil
    
    var totalCalories: Double { foods.reduce(0) { $0 + ($1.food.calories * $1.portion) } }
    var totalProtein: Double { foods.reduce(0) { $0 + ($1.food.protein * $1.portion) } }
    var totalCarbs: Double { foods.reduce(0) { $0 + ($1.food.carbs * $1.portion) } }
    var totalFat: Double { foods.reduce(0) { $0 + ($1.food.fat * $1.portion) } }
    
    var calorieDeficit: Double? {
        guard let bmr = bmr, let activeEnergy = activeEnergy else { return nil }
        return (bmr + activeEnergy) - totalCalories
    }
    
    var body: some View {
        VStack(spacing: 15) {
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
            
            if let deficit = calorieDeficit {
                Divider()
                HStack {
                    Text("热量缺口")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(deficit)) kcal")
                        .font(.headline)
                        .foregroundColor(deficit > 0 ? .green : .red)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
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
    @Binding var selectedFoods: [SelectedFoodItem]
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietTag.name, ascending: true)],
        animation: .default)
    private var allFoods: FetchedResults<DietTag>
    
    @State private var searchText = ""
    
    var filteredFoods: [DietTag] {
        if searchText.isEmpty {
            return Array(allFoods)
        } else {
            return allFoods.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredFoods) { food in
                    FoodPickerRow(food: food) { portion in
                        selectedFoods.append(SelectedFoodItem(food: food, portion: portion))
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索食物")
            .navigationTitle("选择食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct FoodPickerRow: View {
    let food: DietTag
    let onSelect: (Double) -> Void
    @State private var portion: Double = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(food.name ?? "未知")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int(food.calories)) kcal/份")
                    Text("P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fat))")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            HStack {
                Text("份数:")
                    .foregroundColor(.primary)
                Stepper(value: $portion, in: 0.5...10, step: 0.5) {
                    Text("\(String(format: "%.1f", portion))")
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: 150)
                
                Spacer()
                
                Button("添加") {
                    onSelect(portion)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()
