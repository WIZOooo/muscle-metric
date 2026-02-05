import SwiftUI
import CoreData
import HealthKit
import Combine
import UIKit

struct DietRecordDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var record: DietRecord
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UserProfile.id, ascending: true)],
        animation: .default)
    private var userProfiles: FetchedResults<UserProfile>
    
    var userProfile: UserProfile? { userProfiles.first }
    
    var bmr: Double {
        guard let weight = userProfile?.weight, weight > 0 else { return 0 }
        return weight * 24
    }
    
    @State private var showFoodPicker = false
    @State private var showCopiedAlert = false
    
    var entries: [DietEntry] {
        let set = record.entries as? Set<DietEntry> ?? []
        return set.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    var selectedFoodItems: [SelectedFoodItem] {
        entries.compactMap { entry in
            guard let food = entry.foodTag else { return nil }
            let portion = entry.portion == 0 ? 1.0 : entry.portion
            return SelectedFoodItem(food: food, portion: portion)
        }
    }
    
    private var customDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }
    
    var body: some View {
        VStack {
            List {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("日期")
                        Spacer()
                        ZStack(alignment: .trailing) {
                            Text(customDateFormatter.string(from: record.date ?? Date()))
                                .foregroundColor(.secondary)
                            DatePicker("", selection: Binding($record.date, replacingNilWith: Date()), displayedComponents: .date)
                                .labelsHidden()
                                .opacity(0.011)
                        }
                    }
                    
                    HStack {
                        Text("基础代谢")
                        Spacer()
                        Text("\(Int(bmr)) kcal")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("活动热量")
                        Spacer()
                        TextField("0", value: $record.activeEnergy, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)) { _ in
                                saveContext()
                            }
                            .onSubmit {
                                saveContext()
                            }
                        Text("kcal")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Button(action: refreshActiveEnergy) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                Section(header: Text("已选食物")) {
                    ForEach(entries) { entry in
                        if let food = entry.foodTag {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.name ?? "未知")
                                    Text("份数: \(String(format: "%.1f", entry.portion == 0 ? 1.0 : entry.portion))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(food.calories * (entry.portion == 0 ? 1.0 : entry.portion))) kcal")
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
            .scrollDismissesKeyboard(.immediately)
            
            DietSummaryView(foods: selectedFoodItems, bmr: bmr, activeEnergy: record.activeEnergy)
                .padding()
                .background(Color(.systemGray6))
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
                get: { [] }, 
                set: { newItems in
                    for item in newItems {
                        addEntry(item: item)
                    }
                }
            ))
        }
        .onAppear {
             if record.activeEnergy == 0 {
                 refreshActiveEnergy()
             }
        }
    }
    
    private func refreshActiveEnergy() {
        // Temporarily disabled HealthKit integration
        /*
        guard let date = record.date else { return }
        HealthKitManager.shared.requestAuthorization { success, _ in
            if success {
                HealthKitManager.shared.fetchActiveEnergy(for: date) { energy in
                    if let energy = energy {
                        DispatchQueue.main.async {
                            record.activeEnergy = energy
                            saveContext()
                        }
                    }
                }
            }
        }
        */
    }
    
    private func addEntry(item: SelectedFoodItem) {
        let newEntry = DietEntry(context: viewContext)
        newEntry.id = UUID()
        newEntry.foodTag = item.food
        newEntry.portion = item.portion
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
        
        for item in selectedFoodItems {
            let food = item.food
            let portion = item.portion
            let cal = food.calories * portion
            let p = food.protein * portion
            let c = food.carbs * portion
            let f = food.fat * portion
            
            text += "- \(food.name ?? "") (x\(String(format: "%.1f", portion))): \(Int(cal)) kcal (P:\(Int(p)) C:\(Int(c)) F:\(Int(f)))\n"
            totalCal += cal
            totalP += p
            totalC += c
            totalF += f
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

class HealthKitManager {
    static let shared = HealthKitManager()
    
    let healthStore = HKHealthStore()
    
    private init() {}
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "com.muscleMetric", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"]))
            return
        }
        
        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set = [activeEnergyType]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            completion(success, error)
        }
    }
    
    func fetchActiveEnergy(for date: Date, completion: @escaping (Double?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(nil)
            return
        }
        
        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: activeEnergyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                completion(nil)
                return
            }
            
            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            completion(calories)
        }
        
        healthStore.execute(query)
    }
}
