import SwiftUI
import CoreData
import HealthKit

struct MeasurementEntryListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MeasurementEntry.timestamp, ascending: false)],
        animation: .default
    )
    private var entries: FetchedResults<MeasurementEntry>

    @State private var isPresentingAdd = false

    var body: some View {
        List {
            if entries.isEmpty {
                Text("暂无记录")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        MeasurementEntryDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDateTime(entry.timestamp ?? Date()))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            if let summary = summaryText(for: entry), !summary.isEmpty {
                                Text(summary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("测量数据")
        .toolbar {
            Button {
                isPresentingAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            NavigationStack {
                AddMeasurementEntryView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { entries[$0] }.forEach(viewContext.delete)
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    private func summaryText(for entry: MeasurementEntry) -> String? {
        var parts: [String] = []

        if entry.weightKg > 0 { parts.append("体重 \(formatNumber(entry.weightKg))kg") }
        if entry.waistCm > 0 { parts.append("腰围 \(formatNumber(entry.waistCm))cm") }
        if entry.chestCm > 0 { parts.append("胸围 \(formatNumber(entry.chestCm))cm") }
        if entry.hipCm > 0 { parts.append("臀围 \(formatNumber(entry.hipCm))cm") }
        if entry.shoulderWidthCm > 0 { parts.append("肩宽 \(formatNumber(entry.shoulderWidthCm))cm") }
        if entry.armLeftCm > 0 { parts.append("左臂 \(formatNumber(entry.armLeftCm))cm") }
        if entry.armRightCm > 0 { parts.append("右臂 \(formatNumber(entry.armRightCm))cm") }
        if entry.thighLeftCm > 0 { parts.append("左大腿 \(formatNumber(entry.thighLeftCm))cm") }
        if entry.thighRightCm > 0 { parts.append("右大腿 \(formatNumber(entry.thighRightCm))cm") }
        if entry.calfLeftCm > 0 { parts.append("左小腿 \(formatNumber(entry.calfLeftCm))cm") }
        if entry.calfRightCm > 0 { parts.append("右小腿 \(formatNumber(entry.calfRightCm))cm") }

        return parts.prefix(3).joined(separator: "，")
    }
}

private struct AddMeasurementEntryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg = ""
    @State private var bodyFatPercent = ""
    @State private var leanBodyMassKg = ""

    @State private var chestCm = ""
    @State private var waistCm = ""
    @State private var hipCm = ""
    @State private var shoulderWidthCm = ""

    @State private var armLeftCm = ""
    @State private var armRightCm = ""
    @State private var thighLeftCm = ""
    @State private var thighRightCm = ""
    @State private var calfLeftCm = ""
    @State private var calfRightCm = ""

    @State private var note = ""

    @State private var errorMessage: String?
    @State private var isSyncingFromHealth = false

    var body: some View {
        Form {
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Section(header: Text("体重体脂")) {
                numberRow(title: "体重", unit: "kg", text: $weightKg)
                numberRow(title: "体脂率", unit: "%", text: $bodyFatPercent)
                numberRow(title: "去脂体重", unit: "kg", text: $leanBodyMassKg)
            }

            Section {
                Button {
                    Task { await syncFromHealthApp() }
                } label: {
                    HStack {
                        Text("从健康App同步今日数据")
                        Spacer()
                        if isSyncingFromHealth {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncingFromHealth)
            }

            Section(header: Text("躯干")) {
                numberRow(title: "胸围", unit: "cm", text: $chestCm)
                numberRow(title: "腰围", unit: "cm", text: $waistCm)
                numberRow(title: "臀围", unit: "cm", text: $hipCm)
                numberRow(title: "肩宽", unit: "cm", text: $shoulderWidthCm)
            }

            Section(header: Text("上肢")) {
                numberRow(title: "臂围（左）", unit: "cm", text: $armLeftCm)
                numberRow(title: "臂围（右）", unit: "cm", text: $armRightCm)
            }

            Section(header: Text("下肢")) {
                numberRow(title: "大腿围（左）", unit: "cm", text: $thighLeftCm)
                numberRow(title: "大腿围（右）", unit: "cm", text: $thighRightCm)
                numberRow(title: "小腿围（左）", unit: "cm", text: $calfLeftCm)
                numberRow(title: "小腿围（右）", unit: "cm", text: $calfRightCm)
            }

            Section(header: Text("备注")) {
                TextField("可选", text: $note, axis: .vertical)
            }
        }
        .navigationTitle("新增测量")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
            }
        }
    }

    private func numberRow(title: String, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(unit)
        }
    }

    private func parseDouble(_ text: String) -> Double {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        return Double(t) ?? 0
    }

    private func hasAnyValue() -> Bool {
        let values = [
            parseDouble(weightKg),
            parseDouble(bodyFatPercent),
            parseDouble(leanBodyMassKg),
            parseDouble(chestCm),
            parseDouble(waistCm),
            parseDouble(hipCm),
            parseDouble(shoulderWidthCm),
            parseDouble(armLeftCm),
            parseDouble(armRightCm),
            parseDouble(thighLeftCm),
            parseDouble(thighRightCm),
            parseDouble(calfLeftCm),
            parseDouble(calfRightCm),
        ]
        return values.contains(where: { $0 > 0 })
    }

    private func save() {
        guard hasAnyValue() else {
            errorMessage = "请至少填写一项测量数据"
            return
        }

        let entry = MeasurementEntry(context: viewContext)
        entry.id = UUID()
        entry.timestamp = Date()
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)

        entry.weightKg = parseDouble(weightKg)
        entry.bodyFatPercent = parseDouble(bodyFatPercent)
        entry.leanBodyMassKg = parseDouble(leanBodyMassKg)
        entry.chestCm = parseDouble(chestCm)
        entry.waistCm = parseDouble(waistCm)
        entry.hipCm = parseDouble(hipCm)
        entry.shoulderWidthCm = parseDouble(shoulderWidthCm)
        entry.armLeftCm = parseDouble(armLeftCm)
        entry.armRightCm = parseDouble(armRightCm)
        entry.thighLeftCm = parseDouble(thighLeftCm)
        entry.thighRightCm = parseDouble(thighRightCm)
        entry.calfLeftCm = parseDouble(calfLeftCm)
        entry.calfRightCm = parseDouble(calfRightCm)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func syncFromHealthApp() async {
        await MainActor.run {
            errorMessage = nil
            isSyncingFromHealth = true
        }

        do {
            guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass),
                  let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
                  let leanBodyMassType = HKObjectType.quantityType(forIdentifier: .leanBodyMass) else {
                await MainActor.run {
                    errorMessage = "无法读取健康数据类型"
                    isSyncingFromHealth = false
                }
                return
            }

            try await requestAuthorization(readTypes: [bodyMassType, bodyFatType, leanBodyMassType])

            async let weight = fetchMostRecentValue(identifier: .bodyMass, unit: .gramUnit(with: .kilo), date: Date())
            async let bodyFatRaw = fetchMostRecentValue(identifier: .bodyFatPercentage, unit: .percent(), date: Date())
            async let lean = fetchMostRecentValue(identifier: .leanBodyMass, unit: .gramUnit(with: .kilo), date: Date())

            let (weightKgValue, bodyFatValueRaw, leanKgValue) = try await (weight, bodyFatRaw, lean)

            let bodyFatValue: Double? = bodyFatValueRaw.map { raw in
                raw <= 1.0 ? raw * 100.0 : raw
            }

            await MainActor.run {
                if let weightKgValue, weightKgValue > 0 {
                    weightKg = formatNumber(weightKgValue, precision: 1)
                }
                if let bodyFatValue, bodyFatValue > 0 {
                    bodyFatPercent = formatNumber(bodyFatValue, precision: 1)
                }
                if let leanKgValue, leanKgValue > 0 {
                    leanBodyMassKg = formatNumber(leanKgValue, precision: 1)
                }

                if (weightKgValue ?? 0) <= 0 && (bodyFatValue ?? 0) <= 0 && (leanKgValue ?? 0) <= 0 {
                    errorMessage = "健康App 今日暂无体重/体脂/去脂体重数据"
                }
                isSyncingFromHealth = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "同步失败：\(error.localizedDescription)"
                isSyncingFromHealth = false
            }
        }
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitManager.shared.requestAuthorization(readTypes: readTypes) { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fetchMostRecentValue(identifier: HKQuantityTypeIdentifier, unit: HKUnit, date: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitManager.shared.fetchMostRecentQuantity(identifier: identifier, unit: unit, for: date) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct MeasurementEntryDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @ObservedObject var entry: MeasurementEntry
    @State private var previousEntry: MeasurementEntry?
    @State private var errorMessage: String?
    @State private var isSyncingFromHealth = false
    @State private var isEditing = false

    @State private var editWeightKg = ""
    @State private var editBodyFatPercent = ""
    @State private var editLeanBodyMassKg = ""

    @State private var editChestCm = ""
    @State private var editWaistCm = ""
    @State private var editHipCm = ""
    @State private var editShoulderWidthCm = ""

    @State private var editArmLeftCm = ""
    @State private var editArmRightCm = ""
    @State private var editThighLeftCm = ""
    @State private var editThighRightCm = ""
    @State private var editCalfLeftCm = ""
    @State private var editCalfRightCm = ""

    @State private var editNote = ""

    var body: some View {
        Form {
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Section {
                Button {
                    Task { await syncFromHealthAppAndOverwrite() }
                } label: {
                    HStack {
                        Text("从健康App同步并覆盖")
                        Spacer()
                        if isSyncingFromHealth {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncingFromHealth || isEditing)
            }

            Section(header: Text("时间")) {
                Text(formatDateTime(entry.timestamp ?? Date()))
            }

            if let previousEntry, let ts = previousEntry.timestamp {
                Section(header: Text("对比基准")) {
                    Text(formatDateTime(ts))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Section(header: Text("对比基准")) {
                    Text("暂无更早记录，无法对比")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if isEditing {
                Section(header: Text("体重体脂")) {
                    numberRow(title: "体重", unit: "kg", text: $editWeightKg)
                    numberRow(title: "体脂率", unit: "%", text: $editBodyFatPercent)
                    numberRow(title: "去脂体重", unit: "kg", text: $editLeanBodyMassKg)
                }

                Section(header: Text("躯干")) {
                    numberRow(title: "胸围", unit: "cm", text: $editChestCm)
                    numberRow(title: "腰围", unit: "cm", text: $editWaistCm)
                    numberRow(title: "臀围", unit: "cm", text: $editHipCm)
                    numberRow(title: "肩宽", unit: "cm", text: $editShoulderWidthCm)
                }

                Section(header: Text("上肢")) {
                    numberRow(title: "臂围（左）", unit: "cm", text: $editArmLeftCm)
                    numberRow(title: "臂围（右）", unit: "cm", text: $editArmRightCm)
                }

                Section(header: Text("下肢")) {
                    numberRow(title: "大腿围（左）", unit: "cm", text: $editThighLeftCm)
                    numberRow(title: "大腿围（右）", unit: "cm", text: $editThighRightCm)
                    numberRow(title: "小腿围（左）", unit: "cm", text: $editCalfLeftCm)
                    numberRow(title: "小腿围（右）", unit: "cm", text: $editCalfRightCm)
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $editNote, axis: .vertical)
                }
            } else {
                Section(header: Text("体重体脂")) {
                    metricRow(title: "体重", unit: "kg", current: entry.weightKg, previous: previousEntry?.weightKg, precision: 1)
                    metricRow(title: "体脂率", unit: "%", current: entry.bodyFatPercent, previous: previousEntry?.bodyFatPercent, precision: 1)
                    metricRow(title: "去脂体重", unit: "kg", current: entry.leanBodyMassKg, previous: previousEntry?.leanBodyMassKg, precision: 1)
                }

                Section(header: Text("躯干")) {
                    metricRow(title: "胸围", unit: "cm", current: entry.chestCm, previous: previousEntry?.chestCm, precision: 1)
                    metricRow(title: "腰围", unit: "cm", current: entry.waistCm, previous: previousEntry?.waistCm, precision: 1)
                    metricRow(title: "臀围", unit: "cm", current: entry.hipCm, previous: previousEntry?.hipCm, precision: 1)
                    metricRow(title: "肩宽", unit: "cm", current: entry.shoulderWidthCm, previous: previousEntry?.shoulderWidthCm, precision: 1)
                }

                Section(header: Text("上肢")) {
                    metricRow(title: "臂围（左）", unit: "cm", current: entry.armLeftCm, previous: previousEntry?.armLeftCm, precision: 1)
                    metricRow(title: "臂围（右）", unit: "cm", current: entry.armRightCm, previous: previousEntry?.armRightCm, precision: 1)
                }

                Section(header: Text("下肢")) {
                    metricRow(title: "大腿围（左）", unit: "cm", current: entry.thighLeftCm, previous: previousEntry?.thighLeftCm, precision: 1)
                    metricRow(title: "大腿围（右）", unit: "cm", current: entry.thighRightCm, previous: previousEntry?.thighRightCm, precision: 1)
                    metricRow(title: "小腿围（左）", unit: "cm", current: entry.calfLeftCm, previous: previousEntry?.calfLeftCm, precision: 1)
                    metricRow(title: "小腿围（右）", unit: "cm", current: entry.calfRightCm, previous: previousEntry?.calfRightCm, precision: 1)
                }

                if let note = entry.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(header: Text("备注")) {
                        Text(note)
                    }
                }
            }
        }
        .navigationTitle("测量详情")
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        errorMessage = nil
                        isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveEdits()
                    }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("编辑") {
                        beginEditing()
                    }
                }
            }
        }
        .task {
            loadPreviousEntry()
        }
    }

    private func loadPreviousEntry() {
        guard let ts = entry.timestamp else {
            previousEntry = nil
            return
        }

        let request = NSFetchRequest<MeasurementEntry>(entityName: "MeasurementEntry")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.predicate = NSPredicate(format: "timestamp < %@", ts as NSDate)
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        do {
            previousEntry = try viewContext.fetch(request).first
        } catch {
            previousEntry = nil
        }
    }

    private func beginEditing() {
        errorMessage = nil
        isEditing = true

        editWeightKg = entry.weightKg > 0 ? formatNumber(entry.weightKg, precision: 1) : ""
        editBodyFatPercent = entry.bodyFatPercent > 0 ? formatNumber(entry.bodyFatPercent, precision: 1) : ""
        editLeanBodyMassKg = entry.leanBodyMassKg > 0 ? formatNumber(entry.leanBodyMassKg, precision: 1) : ""

        editChestCm = entry.chestCm > 0 ? formatNumber(entry.chestCm, precision: 1) : ""
        editWaistCm = entry.waistCm > 0 ? formatNumber(entry.waistCm, precision: 1) : ""
        editHipCm = entry.hipCm > 0 ? formatNumber(entry.hipCm, precision: 1) : ""
        editShoulderWidthCm = entry.shoulderWidthCm > 0 ? formatNumber(entry.shoulderWidthCm, precision: 1) : ""

        editArmLeftCm = entry.armLeftCm > 0 ? formatNumber(entry.armLeftCm, precision: 1) : ""
        editArmRightCm = entry.armRightCm > 0 ? formatNumber(entry.armRightCm, precision: 1) : ""
        editThighLeftCm = entry.thighLeftCm > 0 ? formatNumber(entry.thighLeftCm, precision: 1) : ""
        editThighRightCm = entry.thighRightCm > 0 ? formatNumber(entry.thighRightCm, precision: 1) : ""
        editCalfLeftCm = entry.calfLeftCm > 0 ? formatNumber(entry.calfLeftCm, precision: 1) : ""
        editCalfRightCm = entry.calfRightCm > 0 ? formatNumber(entry.calfRightCm, precision: 1) : ""

        editNote = entry.note ?? ""
    }

    private func numberRow(title: String, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(unit)
        }
    }

    private func parseDouble(_ text: String) -> Double {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        return Double(t) ?? 0
    }

    private func hasAnyValueForSave() -> Bool {
        let values = [
            parseDouble(editWeightKg),
            parseDouble(editBodyFatPercent),
            parseDouble(editLeanBodyMassKg),
            parseDouble(editChestCm),
            parseDouble(editWaistCm),
            parseDouble(editHipCm),
            parseDouble(editShoulderWidthCm),
            parseDouble(editArmLeftCm),
            parseDouble(editArmRightCm),
            parseDouble(editThighLeftCm),
            parseDouble(editThighRightCm),
            parseDouble(editCalfLeftCm),
            parseDouble(editCalfRightCm),
        ]
        if values.contains(where: { $0 > 0 }) { return true }
        return !editNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveEdits() {
        errorMessage = nil

        guard hasAnyValueForSave() else {
            errorMessage = "请至少填写一项测量数据或备注"
            return
        }

        entry.weightKg = parseDouble(editWeightKg)
        entry.bodyFatPercent = parseDouble(editBodyFatPercent)
        entry.leanBodyMassKg = parseDouble(editLeanBodyMassKg)

        entry.chestCm = parseDouble(editChestCm)
        entry.waistCm = parseDouble(editWaistCm)
        entry.hipCm = parseDouble(editHipCm)
        entry.shoulderWidthCm = parseDouble(editShoulderWidthCm)

        entry.armLeftCm = parseDouble(editArmLeftCm)
        entry.armRightCm = parseDouble(editArmRightCm)
        entry.thighLeftCm = parseDouble(editThighLeftCm)
        entry.thighRightCm = parseDouble(editThighRightCm)
        entry.calfLeftCm = parseDouble(editCalfLeftCm)
        entry.calfRightCm = parseDouble(editCalfRightCm)

        let noteTrimmed = editNote.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = noteTrimmed.isEmpty ? nil : noteTrimmed

        do {
            try viewContext.save()
            isEditing = false
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func syncFromHealthAppAndOverwrite() async {
        await MainActor.run {
            errorMessage = nil
            isSyncingFromHealth = true
        }

        do {
            guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass),
                  let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
                  let leanBodyMassType = HKObjectType.quantityType(forIdentifier: .leanBodyMass) else {
                await MainActor.run {
                    errorMessage = "无法读取健康数据类型"
                    isSyncingFromHealth = false
                }
                return
            }

            let targetDate = entry.timestamp ?? Date()
            try await requestAuthorization(readTypes: [bodyMassType, bodyFatType, leanBodyMassType])

            async let weight = fetchMostRecentValue(identifier: .bodyMass, unit: .gramUnit(with: .kilo), date: targetDate)
            async let bodyFatRaw = fetchMostRecentValue(identifier: .bodyFatPercentage, unit: .percent(), date: targetDate)
            async let lean = fetchMostRecentValue(identifier: .leanBodyMass, unit: .gramUnit(with: .kilo), date: targetDate)

            let (weightKgValue, bodyFatValueRaw, leanKgValue) = try await (weight, bodyFatRaw, lean)
            let bodyFatValue: Double? = bodyFatValueRaw.map { raw in
                raw <= 1.0 ? raw * 100.0 : raw
            }

            var updated = false
            if let v = weightKgValue, v > 0 {
                entry.weightKg = v
                updated = true
            }
            if let v = bodyFatValue, v > 0 {
                entry.bodyFatPercent = v
                updated = true
            }
            if let v = leanKgValue, v > 0 {
                entry.leanBodyMassKg = v
                updated = true
            }

            guard updated else {
                await MainActor.run {
                    errorMessage = "健康App 在该日期暂无体重/体脂/去脂体重数据"
                    isSyncingFromHealth = false
                }
                return
            }

            try viewContext.save()

            await MainActor.run {
                isSyncingFromHealth = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "同步失败：\(error.localizedDescription)"
                isSyncingFromHealth = false
            }
        }
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitManager.shared.requestAuthorization(readTypes: readTypes) { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fetchMostRecentValue(identifier: HKQuantityTypeIdentifier, unit: HKUnit, date: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitManager.shared.fetchMostRecentQuantity(identifier: identifier, unit: unit, for: date) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func metricRow(title: String, unit: String, current: Double, previous: Double?, precision: Int) -> some View {
        let hasCurrent = current > 0
        let deltaText: String? = {
            guard hasCurrent, let previous, previous > 0 else { return nil }
            let delta = current - previous
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(formatNumber(delta, precision: precision))"
        }()

        return HStack {
            Text(title)
            Spacer()
            if hasCurrent {
                HStack(spacing: 0) {
                    Text(formatNumber(current, precision: precision))
                    if let deltaText {
                        Text("（\(deltaText)）")
                            .foregroundColor(.secondary)
                    }
                    Text(unit)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
            }
        }
    }
}

private func formatNumber(_ value: Double, precision: Int = 1) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = precision
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}
