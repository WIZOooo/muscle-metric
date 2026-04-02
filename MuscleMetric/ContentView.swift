import SwiftUI
import CoreData
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            DietRecordListView()
                .tabItem {
                    Label("饮食", systemImage: "fork.knife")
                }

            TrainingRecordListView()
                .tabItem {
                    Label("自由训练", systemImage: "dumbbell")
                }
            
            TrainingPlanTabView()
                .tabItem {
                    Label("训练计划", systemImage: "calendar")
                }
            
            PersonalInfoView()
                .tabItem {
                    Label("个人信息", systemImage: "person.circle")
                }
        }
    }
}

struct TrainingPlan: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var days: [TrainingPlanDay]
}

struct TrainingPlanDay: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var tips: String?
    var trainingDetail: [TrainingPlanExercise]
    var record: [TrainingPlanRecord]?
}

struct TrainingPlanExercise: Codable, Hashable {
    var name: String
    var rep: String?
    var set: String?
    var rest: String?
}

struct TrainingPlanRecord: Codable, Hashable {
    var time: String?
    var set: String?
    var finishSet: String?
    var maxWeight: String?
    var notes: String?
}

struct StoredTrainingPlan: Identifiable, Hashable {
    var id: String { plan.id }
    var plan: TrainingPlan
    var fileURL: URL
}

enum TrainingPlanStorageError: LocalizedError {
    case iCloudNotSignedIn
    case iCloudContainerUnavailable
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .iCloudNotSignedIn:
            return "iCloud 未登录，请先在系统设置登录 iCloud。"
        case .iCloudContainerUnavailable:
            return "iCloud 容器不可用，请检查是否开启 iCloud Drive / 本应用 iCloud 权限。"
        case .invalidJSON:
            return "JSON 格式不正确，无法导入。"
        }
    }
}

enum TrainingPlanStorage {
    static func plansDirectory() throws -> URL {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            throw TrainingPlanStorageError.iCloudNotSignedIn
        }
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw TrainingPlanStorageError.iCloudContainerUnavailable
        }

        let dir = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TrainingPlans", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAllPlans() async throws -> [StoredTrainingPlan] {
        let dir = try plansDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let jsonURLs = urls.filter { $0.pathExtension.lowercased() == "json" }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var plans: [StoredTrainingPlan] = []
        for url in jsonURLs {
            do {
                let data = try Data(contentsOf: url)
                let plan = try decoder.decode(TrainingPlan.self, from: data)
                plans.append(StoredTrainingPlan(plan: plan, fileURL: url))
            } catch {
                continue
            }
        }

        let sorted = plans.sorted(by: { lhs, rhs in
            let l = (try? lhs.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        })
        return sorted
    }

    static func importPlan(from pickedURL: URL) async throws -> StoredTrainingPlan {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: pickedURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let plan: TrainingPlan
        do {
            plan = try decoder.decode(TrainingPlan.self, from: data)
        } catch {
            throw TrainingPlanStorageError.invalidJSON
        }

        let dir = try plansDirectory()
        let fileName = "training_plan_\(sanitizeFilename(plan.id)).json"
        let destURL = dir.appendingPathComponent(fileName, isDirectory: false)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try data.write(to: destURL, options: [.atomic])

        return StoredTrainingPlan(plan: plan, fileURL: destURL)
    }

    static func savePlan(_ plan: TrainingPlan) async throws -> StoredTrainingPlan {
        let dir = try plansDirectory()
        let fileName = "training_plan_\(sanitizeFilename(plan.id)).json"
        let destURL = dir.appendingPathComponent(fileName, isDirectory: false)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plan)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try data.write(to: destURL, options: [.atomic])
        return StoredTrainingPlan(plan: plan, fileURL: destURL)
    }

    static func deletePlan(planId: String) throws {
        guard !planId.isEmpty else { return }
        let url = try planFileURL(planId: planId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func loadPlan(planId: String) async throws -> TrainingPlan? {
        guard !planId.isEmpty else { return nil }
        let url = try planFileURL(planId: planId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let all = try await loadAllPlans()
            return all.first(where: { $0.plan.id == planId })?.plan
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try Data(contentsOf: url)
        return try decoder.decode(TrainingPlan.self, from: data)
    }

    private static func planFileURL(planId: String) throws -> URL {
        let dir = try plansDirectory()
        let fileName = "training_plan_\(sanitizeFilename(planId)).json"
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }

    static func exportsDirectory() throws -> URL {
        let dir = try plansDirectory().appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sanitizeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }
}

enum TrainingPlanSelectionStorage {
    struct Selection: Codable, Hashable {
        var planId: String
        var planName: String
    }

    static func loadSelection() throws -> Selection? {
        let url = try selectionFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Selection.self, from: data)
    }

    static func saveSelection(planId: String, planName: String) throws {
        let url = try selectionFileURL()
        let selection = Selection(planId: planId, planName: planName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(selection)
        try data.write(to: url, options: [.atomic])
    }

    private static func selectionFileURL() throws -> URL {
        let dir = try TrainingPlanStorage.plansDirectory()
        return dir.appendingPathComponent("selected_plan.json", isDirectory: false)
    }
}

enum TrainingPlanExportService {
    struct Payload: Codable, Hashable {
        var exportedAt: String
        var plan: TrainingPlan
        var records: [ExportedTrainingRecord]
    }

    struct ExportedTrainingRecord: Codable, Hashable {
        var id: String
        var planId: String?
        var planName: String?
        var planDayId: String?
        var planDayTitle: String?
        var timestamp: String?
        var gymId: String?
        var gymName: String?
        var exercises: [ExportedExercise]
    }

    struct ExportedExercise: Codable, Hashable {
        var orderIndex: Int
        var name: String
        var rep: String?
        var rest: String?
        var targetSet: Int
        var finishedSet: Int
        var maxWeight: String?
        var notes: String?
    }

    static func exportPlanAndRecords(plan: TrainingPlan, planId: String, context: NSManagedObjectContext) async throws -> URL {
        let exportedAt = ISO8601DateFormatter().string(from: Date())

        let request = NSFetchRequest<TrainingRecord>(entityName: "TrainingRecord")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TrainingRecord.timestamp, ascending: true)]
        request.predicate = NSPredicate(format: "planId == %@", planId)
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let records = try await context.performAsync {
            try context.fetch(request)
        }

        let iso = ISO8601DateFormatter()
        let exportedRecords: [ExportedTrainingRecord] = records.map { record in
            let entries = (record.entries as? Set<TrainingEntry> ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
            return ExportedTrainingRecord(
                id: record.id?.uuidString ?? "",
                planId: record.planId,
                planName: record.planName,
                planDayId: record.planDayId,
                planDayTitle: record.planDayTitle,
                timestamp: record.timestamp.map { iso.string(from: $0) },
                gymId: record.gymTag?.id?.uuidString,
                gymName: record.gymTag?.name,
                exercises: entries.map { e in
                    ExportedExercise(
                        orderIndex: Int(e.orderIndex),
                        name: (e.exerciseName ?? e.actionTag?.name ?? "").isEmpty ? "训练动作" : (e.exerciseName ?? e.actionTag?.name ?? "训练动作"),
                        rep: e.planRep,
                        rest: e.planRest,
                        targetSet: Int(e.planTargetSet),
                        finishedSet: Int(e.planFinishedSet),
                        maxWeight: e.maxWeight,
                        notes: e.notes
                    )
                }
            )
        }

        let payload = Payload(exportedAt: exportedAt, plan: plan, records: exportedRecords)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        let fileName = "training_plan_export_\(sanitizeFilename(planId))_\(timestampForFilename()).json"
        let url = try TrainingPlanStorage.exportsDirectory().appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private static func sanitizeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }
}

enum TrainingPlanTemplateExportService {
    static func exportTemplate(plan: TrainingPlan, planId: String) async throws -> URL {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plan)

        let fileName = "training_plan_template_\(sanitizeFilename(planId))_\(timestampForFilename()).json"
        let url = try TrainingPlanStorage.exportsDirectory().appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private static func sanitizeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }
}

struct TrainingPlanTabView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @AppStorage("selectedTrainingPlanId") private var selectedTrainingPlanId: String = ""
    @AppStorage("selectedTrainingPlanName") private var selectedTrainingPlanName: String = ""

    @State private var selectedPlan: TrainingPlan?
    @State private var isPresentingDaysSheet = false
    @State private var newRecordDay: TrainingPlanDay?

    @State private var exportURL: URL?
    @State private var isPresentingShare = false
    @State private var isExporting = false

    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    private var pickerButtonTitle: String {
        selectedTrainingPlanName.isEmpty ? "选择计划" : selectedTrainingPlanName
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedPlan {
                    PlanTrainingRecordListView(planId: selectedTrainingPlanId, plan: selectedPlan)
                } else {
                    VStack(spacing: 12) {
                        Text("请选择一个训练计划开始")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("训练计划")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        NavigationLink(pickerButtonTitle) {
                            TrainingPlanListView(
                                selectedPlanId: $selectedTrainingPlanId,
                                selectedPlanName: $selectedTrainingPlanName
                            )
                        }
                        Button("导出模板…") {
                            exportSelectedPlanTemplate()
                        }
                        .disabled(selectedPlan == nil || isExporting)
                        Button("导出…") {
                            exportSelectedPlan()
                        }
                        .disabled(selectedPlan == nil || isExporting)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(item: $newRecordDay) { day in
                if let selectedPlan {
                    NewPlanTrainingRecordView(
                        planId: selectedTrainingPlanId,
                        planName: selectedPlan.name,
                        day: day,
                        plan: selectedPlan
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectedPlan != nil {
                    Button("开始训练") {
                        isPresentingDaysSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            Task { await loadSelectedPlanIfNeeded(force: true) }
            restoreSelectionFromICloudIfNeeded()
        }
        .onChange(of: selectedTrainingPlanId) { _, _ in
            Task { await loadSelectedPlanIfNeeded(force: true) }
            persistSelectionToICloud()
        }
        .onChange(of: selectedTrainingPlanName) { _, _ in
            persistSelectionToICloud()
        }
        .sheet(isPresented: $isPresentingDaysSheet) {
            if let selectedPlan {
                NavigationStack {
                    TrainingPlanDaysSheetView(plan: selectedPlan) { day in
                        isPresentingDaysSheet = false
                        newRecordDay = day
                    }
                }
            } else {
                Text("未选择训练计划")
                    .presentationDetents([.medium])
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $isPresentingShare) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
    }

    private func loadSelectedPlanIfNeeded(force: Bool = false) async {
        if !force, selectedPlan != nil { return }
        guard !selectedTrainingPlanId.isEmpty else {
            await MainActor.run { selectedPlan = nil }
            return
        }
        do {
            let plan = try await TrainingPlanStorage.loadPlan(planId: selectedTrainingPlanId)
            await MainActor.run {
                selectedPlan = plan
                if selectedTrainingPlanName.isEmpty {
                    selectedTrainingPlanName = plan?.name ?? ""
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                isPresentingAlert = true
            }
        }
    }

    private func restoreSelectionFromICloudIfNeeded() {
        if !selectedTrainingPlanId.isEmpty { return }
        do {
            if let selection = try TrainingPlanSelectionStorage.loadSelection() {
                if !selection.planId.isEmpty {
                    selectedTrainingPlanId = selection.planId
                    selectedTrainingPlanName = selection.planName
                }
            }
        } catch {
            return
        }
    }

    private func persistSelectionToICloud() {
        do {
            try TrainingPlanSelectionStorage.saveSelection(planId: selectedTrainingPlanId, planName: selectedTrainingPlanName)
        } catch {
            return
        }
    }

    private func exportSelectedPlan() {
        guard let selectedPlan else { return }
        guard !selectedTrainingPlanId.isEmpty else { return }

        Task {
            await MainActor.run { isExporting = true }
            defer { Task { await MainActor.run { isExporting = false } } }

            do {
                let url = try await TrainingPlanExportService.exportPlanAndRecords(
                    plan: selectedPlan,
                    planId: selectedTrainingPlanId,
                    context: viewContext
                )
                await MainActor.run {
                    exportURL = url
                    isPresentingShare = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isPresentingAlert = true
                }
            }
        }
    }

    private func exportSelectedPlanTemplate() {
        guard let selectedPlan else { return }
        guard !selectedTrainingPlanId.isEmpty else { return }

        Task {
            await MainActor.run { isExporting = true }
            defer { Task { await MainActor.run { isExporting = false } } }

            do {
                let url = try await TrainingPlanTemplateExportService.exportTemplate(
                    plan: selectedPlan,
                    planId: selectedTrainingPlanId
                )
                await MainActor.run {
                    exportURL = url
                    isPresentingShare = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isPresentingAlert = true
                }
            }
        }
    }
}

struct PlanTrainingRecordListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    var planId: String
    var plan: TrainingPlan

    @FetchRequest private var records: FetchedResults<TrainingRecord>

    @State private var rowAnchors: [NSManagedObjectID: Anchor<CGRect>] = [:]
    @State private var pendingDeleteId: NSManagedObjectID?
    @State private var isPresentingDeleteConfirm = false
    @State private var isShowingDeletePopover = false
    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    init(planId: String, plan: TrainingPlan) {
        self.planId = planId
        self.plan = plan
        _records = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \TrainingRecord.timestamp, ascending: false)],
            predicate: NSPredicate(format: "planId == %@", planId),
            animation: .default
        )
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    Text("已选择：\(plan.name)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if records.isEmpty {
                    Text("暂无训练记录")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(records) { record in
                        NavigationLink {
                            PlanTrainingRecordDetailView(record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title ?? record.planDayTitle ?? "训练日")
                                    .foregroundStyle(.primary)

                                Text(formatSubtitle(record))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .anchorPreference(key: TrainingRecordRowAnchorPreferenceKey.self, value: .bounds) {
                            [record.objectID: $0]
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) {
                                pendingDeleteId = record.objectID
                                if rowAnchors[record.objectID] != nil {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        isShowingDeletePopover = true
                                    }
                                } else {
                                    isPresentingDeleteConfirm = true
                                }
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(TrainingRecordRowAnchorPreferenceKey.self) { anchors in
                rowAnchors = anchors
                if isShowingDeletePopover, let id = pendingDeleteId, anchors[id] == nil {
                    isShowingDeletePopover = false
                }
            }
            .confirmationDialog("删除训练记录？", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    deletePendingRecord()
                }
                Button("取消", role: .cancel) { }
            }

            if isShowingDeletePopover {
                GeometryReader { proxy in
                    if let id = pendingDeleteId,
                       let anchor = rowAnchors[id],
                       let record = records.first(where: { $0.objectID == id }) {
                        let rect = proxy[anchor]
                        let popoverWidth = min(300, proxy.size.width - 24)
                        let popoverHeight: CGFloat = 120
                        let x = min(max(rect.midX, popoverWidth / 2 + 12), proxy.size.width - popoverWidth / 2 - 12)
                        let preferAbove = rect.minY - popoverHeight - 10
                        let y: CGFloat = preferAbove >= 0 ? (rect.minY - popoverHeight / 2 - 10) : (rect.maxY + popoverHeight / 2 + 10)

                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissDeletePopover()
                            }

                        DeleteTrainingRecordPopoverView(
                            title: record.title ?? record.planDayTitle ?? "训练日",
                            subtitle: formatSubtitle(record),
                            onDelete: {
                                deleteRecord(record)
                            },
                            onCancel: {
                                dismissDeletePopover()
                            }
                        )
                        .frame(width: popoverWidth)
                        .position(x: x, y: y)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func formatSubtitle(_ record: TrainingRecord) -> String {
        let gymName = record.gymTag?.name ?? "未选择门店"
        let timeText: String
        if let ts = record.timestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            timeText = formatter.string(from: ts)
        } else {
            timeText = ""
        }

        if timeText.isEmpty {
            return gymName
        }
        return "\(timeText) · \(gymName)"
    }

    private func deletePendingRecord() {
        guard let pendingDeleteId else { return }
        do {
            guard let record = try viewContext.existingObject(with: pendingDeleteId) as? TrainingRecord else { return }
            deleteRecord(record)
        } catch {
            alertMessage = error.localizedDescription
            isPresentingAlert = true
        }
    }

    private func deleteRecord(_ record: TrainingRecord) {
        do {
            viewContext.delete(record)
            try viewContext.save()
            dismissDeletePopover()
        } catch {
            alertMessage = error.localizedDescription
            isPresentingAlert = true
        }
    }

    private func dismissDeletePopover() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isShowingDeletePopover = false
        }
        pendingDeleteId = nil
    }
}

struct TrainingRecordRowAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [NSManagedObjectID: Anchor<CGRect>], nextValue: () -> [NSManagedObjectID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, rhs in rhs })
    }
}

struct DeleteTrainingRecordPopoverView: View {
    var title: String
    var subtitle: String
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("删除") {
                    onDelete()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

struct TrainingPlanListView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedPlanId: String
    @Binding var selectedPlanName: String

    @State private var plans: [StoredTrainingPlan] = []
    @State private var searchText: String = ""
    @State private var isImporting = false
    @State private var isWorking = false

    @State private var isPresentingEditor = false
    @State private var editorMode: TrainingPlanTemplateEditorView.Mode = .create
    @State private var editorInitialPlan: TrainingPlan = TrainingPlan(id: UUID().uuidString, name: "", days: [])

    @State private var pendingDelete: StoredTrainingPlan?
    @State private var isPresentingDeleteConfirm = false

    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    var body: some View {
        List {
            if filteredPlans.isEmpty {
                Text("暂无训练计划")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredPlans) { stored in
                    HStack(spacing: 12) {
                        NavigationLink {
                            TrainingPlanTemplateDetailView(
                                storedPlan: stored,
                                selectedPlanId: $selectedPlanId,
                                selectedPlanName: $selectedPlanName,
                                onPlanChanged: {
                                    Task { await reloadPlans() }
                                }
                            )
                        } label: {
                            Text(stored.plan.name)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button("选择") {
                            selectedPlanId = stored.plan.id
                            selectedPlanName = stored.plan.name
                            try? TrainingPlanSelectionStorage.saveSelection(planId: selectedPlanId, planName: selectedPlanName)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("编辑") {
                            editorMode = .edit
                            editorInitialPlan = stored.plan
                            isPresentingEditor = true
                        }
                        .tint(.blue)

                        Button("删除", role: .destructive) {
                            pendingDelete = stored
                            isPresentingDeleteConfirm = true
                        }
                    }
                }
            }
        }
        .navigationTitle("选择训练计划")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索计划名称")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建计划") {
                        editorMode = .create
                        editorInitialPlan = TrainingPlan(id: UUID().uuidString, name: "", days: [])
                        isPresentingEditor = true
                    }
                    Button("导入计划") {
                        isImporting = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isWorking)
            }
        }
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("处理中…")
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .onAppear {
            Task { await reloadPlans() }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importPlan(from: url) }
            case .failure(let error):
                showAlert(message: error.localizedDescription)
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("删除训练计划？", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deletePendingPlan()
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                TrainingPlanTemplateEditorView(mode: editorMode, initialPlan: editorInitialPlan) { savedPlan in
                    Task {
                        await saveEditedPlan(savedPlan)
                    }
                }
            }
        }
    }

    private func reloadPlans() async {
        do {
            let loaded = try await TrainingPlanStorage.loadAllPlans()
            await MainActor.run { plans = loaded }
        } catch {
            showAlert(message: error.localizedDescription)
        }
    }

    private func importPlan(from url: URL) async {
        await MainActor.run { isWorking = true }
        defer { Task { await MainActor.run { isWorking = false } } }

        do {
            _ = try await TrainingPlanStorage.importPlan(from: url)
            await reloadPlans()
        } catch {
            showAlert(message: error.localizedDescription)
        }
    }

    private func showAlert(message: String) {
        alertMessage = message
        isPresentingAlert = true
    }

    private var filteredPlans: [StoredTrainingPlan] {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return plans }
        return plans.filter { $0.plan.name.lowercased().contains(key) }
    }

    private func saveEditedPlan(_ plan: TrainingPlan) async {
        await MainActor.run { isWorking = true }
        defer { Task { await MainActor.run { isWorking = false } } }

        do {
            _ = try await TrainingPlanStorage.savePlan(plan)
            if selectedPlanId == plan.id {
                await MainActor.run { selectedPlanName = plan.name }
                try? TrainingPlanSelectionStorage.saveSelection(planId: selectedPlanId, planName: selectedPlanName)
            }
            await reloadPlans()
            await MainActor.run { isPresentingEditor = false }
        } catch {
            showAlert(message: error.localizedDescription)
        }
    }

    private func deletePendingPlan() {
        guard let stored = pendingDelete else { return }
        do {
            try TrainingPlanStorage.deletePlan(planId: stored.plan.id)
            if selectedPlanId == stored.plan.id {
                selectedPlanId = ""
                selectedPlanName = ""
                try? TrainingPlanSelectionStorage.saveSelection(planId: "", planName: "")
            }
            Task { await reloadPlans() }
        } catch {
            showAlert(message: error.localizedDescription)
        }
    }
}

struct TrainingPlanDaysSheetView: View {
    var plan: TrainingPlan
    var onSelectDay: (TrainingPlanDay) -> Void

    var body: some View {
        List {
            ForEach(plan.days) { day in
                Button(day.title) {
                    onSelectDay(day)
                }
            }
        }
        .navigationTitle(plan.name)
        .presentationDetents([.medium, .large])
    }
}

struct NewPlanTrainingRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    var planId: String
    var planName: String
    var day: TrainingPlanDay
    var plan: TrainingPlan

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TrainingTag.name, ascending: true)],
        predicate: NSPredicate(format: "level == 1"),
        animation: .default
    )
    private var gyms: FetchedResults<TrainingTag>

    @State private var selectedGymId: UUID?
    @State private var isSaving = false

    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    var body: some View {
        Form {
            Section(header: Text("门店")) {
                if gyms.isEmpty {
                    Text("暂无门店标签，请先去标签管理创建一级门店标签。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Picker("请选择门店", selection: $selectedGymId) {
                        Text("未选择").tag(Optional<UUID>.none)
                        ForEach(gyms) { gym in
                            Text(gym.name ?? "未命名").tag(gym.id)
                        }
                    }
                }
            }

            Section(header: Text("训练日")) {
                Text(day.title)
            }
        }
        .navigationTitle("新建训练记录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    save()
                }
                .disabled(isSaving || selectedGym == nil)
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if selectedGymId == nil {
                selectedGymId = gyms.first?.id
            }
        }
    }

    private func save() {
        guard let gym = selectedGym else { return }
        guard !planId.isEmpty else {
            alertMessage = "未选择训练计划"
            isPresentingAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        let record = TrainingRecord(context: viewContext)
        record.id = UUID()
        record.timestamp = Date()
        record.title = day.title
        record.gymTag = gym
        record.planId = planId
        record.planName = planName
        record.planDayId = day.id
        record.planDayTitle = day.title

        for (idx, item) in day.trainingDetail.enumerated() {
            let entry = TrainingEntry(context: viewContext)
            entry.id = UUID()
            entry.orderIndex = Int32(idx)
            entry.record = record
            entry.exerciseName = item.name
            entry.planRep = item.rep
            entry.planRest = item.rest
            entry.planTargetSet = Int16(Int(item.set ?? "") ?? 0)
            entry.planFinishedSet = 0
            entry.maxWeight = ""
            entry.notes = ""
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            isPresentingAlert = true
        }
    }

    private var selectedGym: TrainingTag? {
        guard let id = selectedGymId else { return nil }
        return gyms.first(where: { $0.id == id })
    }
}

struct PlanTrainingRecordDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @ObservedObject var record: TrainingRecord

    var body: some View {
        List {
            Section {
                Text(formatHeader(record))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(sortedEntries, id: \.objectID) { entry in
                NavigationLink {
                    PlanTrainingExerciseView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.exerciseName ?? entry.actionTag?.name ?? "训练动作")

                        Text(formatEntrySubtitle(entry))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(record.title ?? "训练日记录")
        .onAppear {
            viewContext.processPendingChanges()
            viewContext.refresh(record, mergeChanges: true)
            for entry in sortedEntries {
                viewContext.refresh(entry, mergeChanges: true)
            }
        }
        .onDisappear {
            if viewContext.hasChanges {
                try? viewContext.save()
            }
        }
    }

    private var sortedEntries: [TrainingEntry] {
        let set = record.entries as? Set<TrainingEntry> ?? []
        return set.sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private func formatHeader(_ record: TrainingRecord) -> String {
        let gymName = record.gymTag?.name ?? "未选择门店"
        let timeText: String
        if let ts = record.timestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            timeText = formatter.string(from: ts)
        } else {
            timeText = ""
        }

        if timeText.isEmpty {
            return gymName
        }
        return "\(timeText) · \(gymName)"
    }

    private func formatEntrySubtitle(_ entry: TrainingEntry) -> String {
        let total = Int(entry.planTargetSet)
        let done = Int(entry.planFinishedSet)
        let rep = (entry.planRep ?? "").isEmpty ? "" : "次数 \(entry.planRep ?? "")"
        let rest = (entry.planRest ?? "").isEmpty ? "" : "休息 \(entry.planRest ?? "")"
        var parts: [String] = []
        if total > 0 { parts.append("组数 \(done)/\(total)") }
        if !rep.isEmpty { parts.append(rep) }
        if !rest.isEmpty { parts.append(rest) }
        return parts.isEmpty ? "点击记录" : parts.joined(separator: " · ")
    }
}

struct PlanTrainingExerciseView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var entry: TrainingEntry

    @State private var isShowingSetToast = false
    @State private var toastProgress: Double = 0
    @State private var toastGeneration: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            Form {
                Section(header: Text("动作")) {
                    Text(entry.exerciseName ?? entry.actionTag?.name ?? "训练动作")
                }

                Section(header: Text("基本信息")) {
                    if let rep = entry.planRep, !rep.isEmpty {
                        HStack {
                            Text("重复次数")
                            Spacer()
                            Text(rep)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let rest = entry.planRest, !rest.isEmpty {
                        HStack {
                            Text("休息时间")
                            Spacer()
                            Text(rest)
                                .foregroundColor(.secondary)
                        }
                    }
                    if entry.planTargetSet > 0 {
                        HStack {
                            Text("总组数")
                            Spacer()
                            Text("\(Int(entry.planTargetSet))")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("完成进度")) {
                    let total = max(0, Int(entry.planTargetSet))
                    let done = max(0, Int(entry.planFinishedSet))

                    HStack {
                        Text("已完成")
                        Spacer()
                        Text("\(done) / \(total)")
                            .foregroundColor(.secondary)
                    }

                    SetIncrementSlider(isDisabled: total == 0 || done >= total) {
                        guard total > 0 else { return }
                        if Int(entry.planFinishedSet) >= total { return }
                        entry.planFinishedSet = min(entry.planTargetSet, entry.planFinishedSet + 1)
                        try? viewContext.save()
                        feedbackForCompletedSet()
                    }
                }

                Section(header: Text("最大重量")) {
                    MaxWeightInputView(entry: entry)
                }

                Section(header: Text("备忘")) {
                    TextEditor(text: notesBinding())
                        .frame(minHeight: 120)
                }
            }
            .scrollDismissesKeyboard(.immediately)

            if isShowingSetToast {
                CompletedSetToastView(progress: toastProgress)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationTitle("训练动作")
        .onDisappear {
            if viewContext.hasChanges {
                try? viewContext.save()
            }
        }
    }

    private func maxWeightBinding() -> Binding<String> {
        Binding(
            get: { entry.maxWeight ?? "" },
            set: { newValue in
                entry.maxWeight = newValue
                try? viewContext.save()
            }
        )
    }

    private func notesBinding() -> Binding<String> {
        Binding(
            get: { entry.notes ?? "" },
            set: { newValue in
                entry.notes = newValue
                try? viewContext.save()
            }
        )
    }

    private func feedbackForCompletedSet() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        toastGeneration += 1
        let current = toastGeneration

        toastProgress = 1
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isShowingSetToast = true
        }
        withAnimation(.linear(duration: 3)) {
            toastProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard current == toastGeneration else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isShowingSetToast = false
            }
        }
    }
}

struct CompletedSetToastView: View {
    var progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
            .frame(width: 28, height: 28)

            Text("已记录：完成 1 组")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SetIncrementSlider: View {
    var isDisabled: Bool
    var onIncrement: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let height: CGFloat = 44
            let knobSize: CGFloat = 44
            let maxX = max(0, geo.size.width - knobSize)
            let threshold = maxX * 0.82

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(isDisabled ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(height: height)

                Text(isDisabled ? "已完成" : "滑动完成 1 组")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)

                Circle()
                    .fill(isDisabled ? Color.secondary.opacity(0.6) : Color.blue)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: min(max(0, dragX), maxX))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isDisabled else { return }
                                dragX = min(max(0, value.translation.width), maxX)
                            }
                            .onEnded { _ in
                                guard !isDisabled else {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        dragX = 0
                                    }
                                    return
                                }

                                if dragX >= threshold {
                                    onIncrement()
                                }

                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    dragX = 0
                                }
                            }
                    )
                    .allowsHitTesting(!isDisabled)
            }
        }
        .frame(height: 44)
    }
}

struct MaxWeightInputView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var entry: TrainingEntry

    @FetchRequest private var recentEntries: FetchedResults<TrainingEntry>

    init(entry: TrainingEntry) {
        self.entry = entry

        let name = (entry.exerciseName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let gym = entry.record?.gymTag
        let record = entry.record

        let request = NSFetchRequest<TrainingEntry>(entityName: "TrainingEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "record.timestamp", ascending: false)]
        request.fetchLimit = 1

        var predicates: [NSPredicate] = [
            NSPredicate(format: "maxWeight != nil AND maxWeight != ''")
        ]

        if let gym {
            predicates.append(NSPredicate(format: "record.gymTag == %@", gym))
        } else {
            predicates.append(NSPredicate(value: false))
        }

        if !name.isEmpty {
            predicates.append(NSPredicate(format: "exerciseName == %@", name))
        } else {
            predicates.append(NSPredicate(value: false))
        }

        if let record {
            predicates.append(NSPredicate(format: "record != %@", record))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        _recentEntries = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        TextField(placeholderText, text: binding)
    }

    private var placeholderText: String {
        let hint = (recentEntries.first?.maxWeight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if hint.isEmpty {
            return "例如 20kg"
        }
        return "上次：\(hint)"
    }

    private var binding: Binding<String> {
        Binding(
            get: { entry.maxWeight ?? "" },
            set: { newValue in
                entry.maxWeight = newValue
                try? viewContext.save()
            }
        )
    }
}

struct TrainingPlanTemplateDetailView: View {
    @Binding var selectedPlanId: String
    @Binding var selectedPlanName: String

    var storedPlan: StoredTrainingPlan
    var onPlanChanged: () -> Void

    @State private var plan: TrainingPlan
    @State private var isPresentingEditor = false

    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    init(storedPlan: StoredTrainingPlan, selectedPlanId: Binding<String>, selectedPlanName: Binding<String>, onPlanChanged: @escaping () -> Void) {
        self.storedPlan = storedPlan
        self._selectedPlanId = selectedPlanId
        self._selectedPlanName = selectedPlanName
        self.onPlanChanged = onPlanChanged
        _plan = State(initialValue: storedPlan.plan)
    }

    var body: some View {
        List {
            Section(header: Text("计划信息")) {
                HStack {
                    Text("名称")
                    Spacer()
                    Text(plan.name)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("训练日")
                    Spacer()
                    Text("\(plan.days.count)")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("训练日")) {
                if plan.days.isEmpty {
                    Text("暂无训练日")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(plan.days) { day in
                        NavigationLink {
                            TrainingDayDetailView(day: day)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.title)
                                HStack(spacing: 8) {
                                    Text("\(day.trainingDetail.count) 个动作")
                                    if let tips = day.tips, !tips.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("有提示")
                                    }
                                }
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") {
                    isPresentingEditor = true
                }
            }
        }
        .onAppear {
            Task { await reloadPlan() }
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                TrainingPlanTemplateEditorView(mode: .edit, initialPlan: plan) { updated in
                    Task { await save(updated) }
                }
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func reloadPlan() async {
        do {
            if let latest = try await TrainingPlanStorage.loadPlan(planId: storedPlan.plan.id) {
                await MainActor.run { plan = latest }
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                isPresentingAlert = true
            }
        }
    }

    private func save(_ updated: TrainingPlan) async {
        do {
            _ = try await TrainingPlanStorage.savePlan(updated)
            await MainActor.run {
                plan = updated
                isPresentingEditor = false
            }

            if selectedPlanId == updated.id {
                await MainActor.run { selectedPlanName = updated.name }
                try? TrainingPlanSelectionStorage.saveSelection(planId: selectedPlanId, planName: selectedPlanName)
            }
            onPlanChanged()
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                isPresentingAlert = true
            }
        }
    }
}

struct TrainingPlanTemplateEditorView: View {
    enum Mode: Hashable {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss

    var mode: Mode
    var initialPlan: TrainingPlan
    var onSave: (TrainingPlan) -> Void

    @State private var plan: TrainingPlan
    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""

    init(mode: Mode, initialPlan: TrainingPlan, onSave: @escaping (TrainingPlan) -> Void) {
        self.mode = mode
        self.initialPlan = initialPlan
        self.onSave = onSave
        _plan = State(initialValue: initialPlan)
    }

    var body: some View {
        Form {
            Section(header: Text("计划")) {
                TextField("计划名称", text: $plan.name)
            }

            Section(header: Text("训练日")) {
                if plan.days.isEmpty {
                    Text("暂无训练日")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($plan.days) { $day in
                        NavigationLink {
                            TrainingPlanDayEditorView(day: $day)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.title.isEmpty ? "未命名训练日" : day.title)
                                Text("\(day.trainingDetail.count) 个动作")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        plan.days.remove(atOffsets: offsets)
                    }
                }

                Button("新增训练日") {
                    plan.days.append(
                        TrainingPlanDay(
                            id: UUID().uuidString,
                            title: "",
                            tips: "",
                            trainingDetail: [],
                            record: []
                        )
                    )
                }
            }
        }
        .navigationTitle(mode == .create ? "新建计划" : "编辑计划")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    let name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        alertMessage = "请输入计划名称"
                        isPresentingAlert = true
                        return
                    }
                    plan.name = name
                    onSave(plan)
                }
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}

struct TrainingPlanDayEditorView: View {
    @Binding var day: TrainingPlanDay

    var body: some View {
        Form {
            Section(header: Text("训练日")) {
                TextField("训练日名称", text: $day.title)
            }

            Section(header: Text("提示")) {
                TextEditor(text: Binding(
                    get: { day.tips ?? "" },
                    set: { day.tips = $0 }
                ))
                .frame(minHeight: 120)
            }

            Section(header: Text("训练动作")) {
                if day.trainingDetail.isEmpty {
                    Text("暂无训练动作")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(day.trainingDetail.indices, id: \.self) { idx in
                        NavigationLink {
                            TrainingPlanExerciseEditorView(exercise: Binding(
                                get: { day.trainingDetail[idx] },
                                set: { day.trainingDetail[idx] = $0 }
                            ))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.trainingDetail[idx].name.isEmpty ? "未命名动作" : day.trainingDetail[idx].name)
                                Text(formatExerciseSummary(day.trainingDetail[idx]))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        day.trainingDetail.remove(atOffsets: offsets)
                    }
                }

                Button("新增训练动作") {
                    day.trainingDetail.append(TrainingPlanExercise(name: "", rep: "", set: "", rest: ""))
                }
            }
        }
        .navigationTitle(day.title.isEmpty ? "编辑训练日" : day.title)
    }

    private func formatExerciseSummary(_ e: TrainingPlanExercise) -> String {
        var parts: [String] = []
        if let rep = e.rep, !rep.isEmpty { parts.append("次数 \(rep)") }
        if let set = e.set, !set.isEmpty { parts.append("组数 \(set)") }
        if let rest = e.rest, !rest.isEmpty { parts.append("休息 \(rest)") }
        return parts.isEmpty ? "未填写" : parts.joined(separator: " · ")
    }
}

struct TrainingPlanExerciseEditorView: View {
    @Binding var exercise: TrainingPlanExercise

    var body: some View {
        Form {
            Section(header: Text("动作")) {
                TextField("动作名称", text: $exercise.name)
            }

            Section(header: Text("参数")) {
                TextField("重复次数", text: Binding(get: { exercise.rep ?? "" }, set: { exercise.rep = $0 }))
                TextField("组数", text: Binding(get: { exercise.set ?? "" }, set: { exercise.set = $0 }))
                TextField("休息", text: Binding(get: { exercise.rest ?? "" }, set: { exercise.rest = $0 }))
            }
        }
        .navigationTitle(exercise.name.isEmpty ? "编辑动作" : exercise.name)
    }
}

struct TrainingDayDetailView: View {
    var day: TrainingPlanDay

    @State private var expandedIndexes: Set<Int> = []

    var body: some View {
        List {
            if let tips = day.tips, !tips.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(header: Text("提示")) {
                    Text(tips)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(Array(day.trainingDetail.enumerated()), id: \.offset) { index, item in
                Button {
                    toggleExpanded(index)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .foregroundColor(.primary)

                        if expandedIndexes.contains(index) {
                            Text(formatDetail(item))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(day.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    Button("全部折叠") {
                        expandedIndexes.removeAll()
                    }
                    .disabled(expandedIndexes.isEmpty)
                }
            }
        }
    }

    private func toggleExpanded(_ index: Int) {
        if expandedIndexes.contains(index) {
            expandedIndexes.remove(index)
        } else {
            expandedIndexes.insert(index)
        }
    }

    private func formatDetail(_ item: TrainingPlanExercise) -> String {
        var parts: [String] = []
        if let rep = item.rep, !rep.isEmpty { parts.append("次数 \(rep)") }
        if let set = item.set, !set.isEmpty { parts.append("组数 \(set)") }
        if let rest = item.rest, !rest.isEmpty { parts.append("休息 \(rest)") }
        return parts.isEmpty ? "暂无详情" : parts.joined(separator: " · ")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
