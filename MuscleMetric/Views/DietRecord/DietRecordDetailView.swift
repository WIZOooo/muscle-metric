import SwiftUI
import CoreData
import HealthKit
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct RestingEnergyDailyValue: Identifiable, Equatable {
    let date: Date
    let kilocalories: Double
    let usedInAverage: Bool

    var id: Date { date }
}

struct RestingEnergyAverageResult: Equatable {
    let averageKilocalories: Double
    let dailyValues: [RestingEnergyDailyValue]
}

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

    private var effectiveBmr: Double? {
        let storedResting = record.restingEnergy > 0 ? record.restingEnergy : nil
        let resting = restingEnergyFromHealthKit ?? storedResting
        if isBmrSourceResolved == false && resting == nil {
            return nil
        }
        return resting ?? bmr
    }

    private var bmrDisplayText: String {
        let storedResting = record.restingEnergy > 0 ? record.restingEnergy : nil
        let resting = restingEnergyFromHealthKit ?? storedResting
        if isBmrSourceResolved == false && resting == nil {
            return "获取中…"
        }
        return "\(Int(resting ?? bmr)) kcal"
    }
    
    @State private var showFoodPicker = false
    @State private var showCopiedAlert = false
    @State private var isRefreshingActiveEnergy = false
    @State private var showActiveEnergyErrorAlert = false
    @State private var activeEnergyErrorMessage = ""
    @State private var restingEnergyFromHealthKit: Double?
    @State private var restingEnergyDailyValues: [RestingEnergyDailyValue] = []
    @State private var hasAttemptedRestingEnergyAutoFetch = false
    @State private var isBmrSourceResolved = false
    @State private var isRefreshingRestingEnergy = false
    @State private var showRestingEnergyErrorAlert = false
    @State private var restingEnergyErrorMessage = ""
    @State private var showAddDietTagSheet = false
    
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

    private var dayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
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
                        Text(bmrDisplayText)
                            .foregroundColor(.secondary)

                        Button(action: refreshRestingEnergy) {
                            if isRefreshingRestingEnergy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isRefreshingRestingEnergy)
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

                if !restingEnergyDailyValues.isEmpty {
                    Section(header: Text("静息能量（用于基础代谢）")) {
                        ForEach(restingEnergyDailyValues) { item in
                            HStack {
                                Text(dayDateFormatter.string(from: item.date))
                                Spacer()
                                Text("\(Int(item.kilocalories)) kcal")
                                    .foregroundColor(item.usedInAverage ? .secondary : .secondary.opacity(0.6))
                                if !item.usedInAverage {
                                    Text("忽略")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
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
            
            DietSummaryView(foods: selectedFoodItems, bmr: effectiveBmr, activeEnergy: record.activeEnergy)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddDietTagSheet = true
                } label: {
                    Image(systemName: "tag")
                }
            }
        }
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("记录详情已复制到剪切板")
        }
        .sheet(isPresented: $showAddDietTagSheet) {
            AddDietTagView()
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
        .alert("无法获取静息能量", isPresented: $showRestingEnergyErrorAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(restingEnergyErrorMessage)
        }
        .onAppear {
            if record.restingEnergy > 0 {
                restingEnergyFromHealthKit = record.restingEnergy
                isBmrSourceResolved = true
            }
            if !hasAttemptedRestingEnergyAutoFetch {
                hasAttemptedRestingEnergyAutoFetch = true
                autoRefreshRestingEnergy()
            }

            guard record.activeEnergy == 0 else { return }
            guard HKHealthStore.isHealthDataAvailable() else { return }
            guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
            if HealthKitManager.shared.healthStore.authorizationStatus(for: activeEnergyType) == .sharingAuthorized {
                refreshActiveEnergy()
            }
        }
    }

    private func autoRefreshRestingEnergy() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isBmrSourceResolved = true
            return
        }
        guard let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else {
            isBmrSourceResolved = true
            return
        }
        let status = HealthKitManager.shared.healthStore.authorizationStatus(for: restingEnergyType)
        guard status != .sharingDenied else {
            isBmrSourceResolved = true
            return
        }
        refreshRestingEnergy(showError: false)
    }

    private func refreshRestingEnergy() {
        refreshRestingEnergy(showError: true)
    }

    private func refreshRestingEnergy(showError: Bool) {
        guard !isRefreshingRestingEnergy else { return }
        isBmrSourceResolved = false
        guard HKHealthStore.isHealthDataAvailable() else {
            if showError {
                presentRestingEnergyError("当前设备不支持读取健康数据，将使用估算值。")
            }
            isBmrSourceResolved = true
            return
        }

        let date = record.date ?? Date()
        isRefreshingRestingEnergy = true
        HealthKitManager.shared.requestRestingEnergyAuthorization { authResult in
            switch authResult {
            case .success:
                HealthKitManager.shared.fetchRestingEnergyAverage(for: date, days: 3) { fetchResult in
                    DispatchQueue.main.async {
                        isRefreshingRestingEnergy = false
                        isBmrSourceResolved = true
                        switch fetchResult {
                        case .success(let result):
                            restingEnergyFromHealthKit = result.averageKilocalories
                            restingEnergyDailyValues = result.dailyValues.sorted { $0.date > $1.date }
                            record.restingEnergy = result.averageKilocalories
                            saveContext()
                        case .failure:
                            if record.restingEnergy > 0 {
                                restingEnergyFromHealthKit = record.restingEnergy
                            } else {
                                restingEnergyFromHealthKit = nil
                            }
                            restingEnergyDailyValues = []
                            if showError {
                                presentRestingEnergyError("未能读取到近三天的静息能量，将使用估算值。")
                            }
                        }
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    isRefreshingRestingEnergy = false
                    isBmrSourceResolved = true
                    if record.restingEnergy > 0 {
                        restingEnergyFromHealthKit = record.restingEnergy
                    } else {
                        restingEnergyFromHealthKit = nil
                    }
                    restingEnergyDailyValues = []
                    if showError {
                        presentRestingEnergyError("未获得健康数据读取权限，将使用估算值。")
                    }
                }
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

    private func presentRestingEnergyError(_ message: String) {
        restingEnergyErrorMessage = message
        showRestingEnergyErrorAlert = true
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
    case restingEnergyTypeUnavailable
    case restingEnergyNoData
    case bodyMassTypeUnavailable
    case bodyFatPercentageTypeUnavailable
    case leanBodyMassTypeUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "当前设备不支持读取健康数据。"
        case .activeEnergyTypeUnavailable:
            return "无法读取活动能量类型。"
        case .restingEnergyTypeUnavailable:
            return "无法读取静息能量类型。"
        case .restingEnergyNoData:
            return "未能读取到静息能量数据。"
        case .bodyMassTypeUnavailable:
            return "无法读取体重类型。"
        case .bodyFatPercentageTypeUnavailable:
            return "无法读取体脂率类型。"
        case .leanBodyMassTypeUnavailable:
            return "无法读取去脂体重类型。"
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
        requestAuthorization(readTypes: [activeEnergyType], completion: completion)
    }

    func requestAuthorization(readTypes: Set<HKObjectType>, completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }

        let typesToShare: Set<HKSampleType> = []
        healthStore.requestAuthorization(toShare: typesToShare, read: readTypes) { success, error in
            if success {
                completion(.success(()))
            } else if let error {
                completion(.failure(error))
            } else {
                completion(.failure(HealthKitManagerError.authorizationDenied))
            }
        }
    }

    func requestRestingEnergyAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }

        guard let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else {
            completion(.failure(HealthKitManagerError.restingEnergyTypeUnavailable))
            return
        }

        requestAuthorization(readTypes: [restingEnergyType], completion: completion)
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

    func fetchRestingEnergy(for date: Date, completion: @escaping (Result<Double, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }

        guard let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else {
            completion(.failure(HealthKitManagerError.restingEnergyTypeUnavailable))
            return
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: restingEnergyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            if let error {
                completion(.failure(error))
                return
            }

            let calories = (result?.sumQuantity() ?? HKQuantity(unit: .kilocalorie(), doubleValue: 0)).doubleValue(for: .kilocalorie())
            completion(.success(calories.rounded(.toNearestOrAwayFromZero)))
        }

        healthStore.execute(query)
    }

    func fetchRestingEnergyAverage(for date: Date, days: Int, completion: @escaping (Result<RestingEnergyAverageResult, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }

        guard let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else {
            completion(.failure(HealthKitManagerError.restingEnergyTypeUnavailable))
            return
        }

        let days = max(days, 1)
        let calendar = Calendar.current
        let baseDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let baseStartOfDay = calendar.startOfDay(for: baseDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: baseStartOfDay)!
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: baseStartOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endOfDay, options: .strictStartDate)
        let anchorDate = baseStartOfDay
        let interval = DateComponents(day: 1)

        let query = HKStatisticsCollectionQuery(
            quantityType: restingEnergyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, results, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let results else {
                completion(.failure(HealthKitManagerError.restingEnergyNoData))
                return
            }

            var dayValues: [(Date, Double)] = []
            let enumerationEnd = endOfDay.addingTimeInterval(-1)
            results.enumerateStatistics(from: startDate, to: enumerationEnd) { stats, _ in
                guard stats.startDate < endOfDay else { return }
                let value = (stats.sumQuantity() ?? HKQuantity(unit: .kilocalorie(), doubleValue: 0)).doubleValue(for: .kilocalorie())
                dayValues.append((stats.startDate, value))
            }

            let nonZeroValues = dayValues.map(\.1).filter { $0 > 0 }
            guard !nonZeroValues.isEmpty else {
                completion(.failure(HealthKitManagerError.restingEnergyNoData))
                return
            }

            let average = nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
            let dailyValues = dayValues
                .map { (dayStart, value) in
                    RestingEnergyDailyValue(
                        date: dayStart,
                        kilocalories: value.rounded(.toNearestOrAwayFromZero),
                        usedInAverage: value > 0
                    )
                }
                .sorted { $0.date > $1.date }
            completion(.success(RestingEnergyAverageResult(averageKilocalories: average.rounded(.toNearestOrAwayFromZero), dailyValues: dailyValues)))
        }

        healthStore.execute(query)
    }

    func fetchMostRecentQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        for date: Date,
        completion: @escaping (Result<Double?, Error>) -> Void
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthKitManagerError.healthDataNotAvailable))
            return
        }

        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            switch identifier {
            case .bodyMass:
                completion(.failure(HealthKitManagerError.bodyMassTypeUnavailable))
            case .bodyFatPercentage:
                completion(.failure(HealthKitManagerError.bodyFatPercentageTypeUnavailable))
            case .leanBodyMass:
                completion(.failure(HealthKitManagerError.leanBodyMassTypeUnavailable))
            default:
                completion(.failure(HealthKitManagerError.authorizationDenied))
            }
            return
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let sample = samples?.first as? HKQuantitySample else {
                completion(.success(nil))
                return
            }

            completion(.success(sample.quantity.doubleValue(for: unit)))
        }

        healthStore.execute(query)
    }
}
