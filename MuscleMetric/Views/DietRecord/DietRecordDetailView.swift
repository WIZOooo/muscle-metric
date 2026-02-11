import SwiftUI
import CoreData
import HealthKit
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    @State private var isRefreshingActiveEnergy = false
    @State private var showActiveEnergyErrorAlert = false
    @State private var activeEnergyErrorMessage = ""
    
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
                            .onKeyboardWillHide {
                                saveContext()
                            }
                            .onSubmit {
                                saveContext()
                            }
                        Text("kcal")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Button(action: refreshActiveEnergy) {
                            if isRefreshingActiveEnergy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isRefreshingActiveEnergy)
                    }
                }
                
                Section {
                    ForEach(entries) { entry in
                        if let food = entry.foodTag {
                            let portion = entry.portion == 0 ? 1.0 : entry.portion
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.name ?? "未知")
                                    Text("份数: \(String(format: "%.1f", portion))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("蛋白质 \(String(format: "%.1f", food.protein * portion))g · 碳水 \(String(format: "%.1f", food.carbs * portion))g · 脂肪 \(String(format: "%.1f", food.fat * portion))g")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(food.calories * portion)) kcal")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteEntry)
                } header: {
                    HStack {
                        Text("已选食物")
                        Spacer()
                        Button(action: { showFoodPicker = true }) {
                            Label("添加", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
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
        .alert("无法获取活动热量", isPresented: $showActiveEnergyErrorAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(activeEnergyErrorMessage)
        }
        .onAppear {
            guard record.activeEnergy == 0 else { return }
            guard HKHealthStore.isHealthDataAvailable() else { return }
            guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
            if HealthKitManager.shared.healthStore.authorizationStatus(for: activeEnergyType) == .sharingAuthorized {
                refreshActiveEnergy()
            }
        }
    }
    
    private func refreshActiveEnergy() {
        guard !isRefreshingActiveEnergy else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            presentActiveEnergyError("当前设备不支持读取健康数据。")
            return
        }

        let date = record.date ?? Date()
        isRefreshingActiveEnergy = true
        HealthKitManager.shared.requestAuthorization { authResult in
            switch authResult {
            case .success:
                HealthKitManager.shared.fetchActiveEnergy(for: date) { fetchResult in
                    DispatchQueue.main.async {
                        isRefreshingActiveEnergy = false
                        switch fetchResult {
                        case .success(let energy):
                            record.activeEnergy = energy.rounded(.toNearestOrAwayFromZero)
                            saveContext()
                        case .failure(let error):
                            presentActiveEnergyError(error.localizedDescription)
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    isRefreshingActiveEnergy = false
                    presentActiveEnergyError(error.localizedDescription)
                }
            }
        }
    }

    private func presentActiveEnergyError(_ message: String) {
        activeEnergyErrorMessage = message
        showActiveEnergyErrorAlert = true
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

#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        showCopiedAlert = true
    }
}

extension View {
    @ViewBuilder
    func onKeyboardWillHide(_ action: @escaping () -> Void) -> some View {
#if canImport(UIKit)
        onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)) { _ in
            action()
        }
#else
        self
#endif
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

enum HealthKitManagerError: LocalizedError {
    case healthDataNotAvailable
    case activeEnergyTypeUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "当前设备不支持读取健康数据。"
        case .activeEnergyTypeUnavailable:
            return "无法读取活动能量类型。"
        case .authorizationDenied:
            return "未获得健康数据读取权限。"
        }
    }
}

class HealthKitManager {
    static let shared = HealthKitManager()
    
    let healthStore = HKHealthStore()
    
    private init() {}
    
    func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }
        
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(.failure(HealthKitManagerError.activeEnergyTypeUnavailable))
            return
        }
        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set<HKObjectType> = [activeEnergyType]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if success {
                completion(.success(()))
            } else if let error {
                completion(.failure(error))
            } else {
                completion(.failure(HealthKitManagerError.authorizationDenied))
            }
        }
    }
    
    func fetchActiveEnergy(for date: Date, completion: @escaping (Result<Double, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }
        
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(.failure(HealthKitManagerError.activeEnergyTypeUnavailable))
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: activeEnergyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            if let error {
                completion(.failure(error))
                return
            }

            let calories = (result?.sumQuantity() ?? HKQuantity(unit: .kilocalorie(), doubleValue: 0)).doubleValue(for: .kilocalorie())
            completion(.success(calories.rounded(.toNearestOrAwayFromZero)))
        }
        
        healthStore.execute(query)
    }
}
