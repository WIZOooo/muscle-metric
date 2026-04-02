import SwiftUI
import CoreData
import CloudKit
import Combine

struct PersonalInfoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UserProfile.id, ascending: true)],
        animation: .default)
    private var profiles: FetchedResults<UserProfile>

    @State private var isManualSyncing = false
    @State private var syncResultMessage: String?
    @State private var iCloudStatusMessage: String = "iCloud 状态：检测中..."
    @State private var lastCloudKitEventMessage: String?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isPresentingShare = false
    
    var body: some View {
        NavigationStack {
            if let profile = profiles.first {
                Form {
                    Section(header: Text("基本资料")) {
                        HStack {
                            Text("年龄")
                            Spacer()
                            TextField("0", value: Binding(
                                get: { Int(profile.age) },
                                set: { newValue in
                                    profile.age = Int16(newValue)
                                    saveContext()
                                }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            Text("岁")
                        }
                        
                        Picker("性别", selection: Binding(
                            get: { profile.gender ?? "男" },
                            set: { newValue in
                                profile.gender = newValue
                                saveContext()
                            }
                        )) {
                            Text("男").tag("男")
                            Text("女").tag("女")
                        }
                    }
                    
                    Section(header: Text("身体数据")) {
                        HStack {
                            Text("身高")
                            Spacer()
                            TextField("0", value: Binding(
                                get: { profile.height },
                                set: { newValue in
                                    profile.height = newValue
                                    saveContext()
                                }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            Text("cm")
                        }
                        
                        HStack {
                            Text("体重")
                            Spacer()
                            TextField("0", value: Binding(
                                get: { profile.weight },
                                set: { newValue in
                                    profile.weight = newValue
                                    saveContext()
                                }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            Text("kg")
                        }
                    }
                    
                    Section(header: Text("目标设定")) {
                        Picker("运动目标", selection: Binding(
                            get: { profile.goal ?? "增肌" },
                            set: { newValue in
                                profile.goal = newValue
                                saveContext()
                            }
                        )) {
                            Text("增肌").tag("增肌")
                            Text("减脂").tag("减脂")
                        }
                    }

                    Section(header: Text("管理")) {
                        NavigationLink("标签管理") {
                            TagManagerView()
                        }
                        NavigationLink("测量数据") {
                            MeasurementEntryListView()
                        }
                    }

                    Section(header: Text("iCloud 同步")) {
                        Text(iCloudStatusMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        if let eventMessage = lastCloudKitEventMessage, !eventMessage.isEmpty {
                            Text(eventMessage)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            Task { await manualSync() }
                        } label: {
                            HStack {
                                Text("手动同步 iCloud 数据")
                                Spacer()
                                if isManualSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isManualSyncing)

                        if let message = syncResultMessage, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("数据导出")) {
                        Button {
                            Task { await exportData() }
                        } label: {
                            HStack {
                                Text("导出本地数据（JSON）")
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isExporting)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .navigationTitle("个人信息")
                .onAppear { refreshICloudStatus() }
                .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification).receive(on: RunLoop.main)) { notification in
                    handleCloudKitEventNotification(notification)
                }
                .sheet(isPresented: $isPresentingShare) {
                    if let exportURL {
                        ActivityView(activityItems: [exportURL])
                    }
                }
            } else {
                Text("正在初始化个人信息...")
                    .onAppear {
                        createDefaultProfile()
                    }
            }
        }
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func createDefaultProfile() {
        let newProfile = UserProfile(context: viewContext)
        newProfile.id = UUID()
        newProfile.age = 25
        newProfile.gender = "男"
        newProfile.goal = "增肌"
        newProfile.height = 175.0
        newProfile.weight = 70.0
        
        saveContext()
    }

    private func manualSync() async {
        await MainActor.run {
            isManualSyncing = true
            syncResultMessage = nil
        }

        do {
            let report = try await CloudManualSyncService.manualSync(container: PersistenceController.shared.container)
            await MainActor.run {
                syncResultMessage = formatSyncReport(report)
                isManualSyncing = false
            }
        } catch {
            await MainActor.run {
                syncResultMessage = "同步失败：\(error.localizedDescription)"
                isManualSyncing = false
            }
        }
    }

    private func formatSyncReport(_ report: SyncReport) -> String {
        let normalized = report.normalizedIdsTotal
        let mergedById = report.mergedByIdTotal
        let mergedByKey = report.mergedBySemanticKeyTotal
        let deleted = report.deletedDuplicatesTotal

        var parts: [String] = []
        parts.append("已完成")
        if normalized > 0 { parts.append("补全主键 \(normalized)") }
        if mergedById > 0 { parts.append("按 UUID 合并 \(mergedById)") }
        if mergedByKey > 0 { parts.append("按语义去重 \(mergedByKey)") }
        if deleted > 0 { parts.append("删除重复项 \(deleted)") }
        return parts.joined(separator: "，")
    }

    private func refreshICloudStatus() {
        Task {
            let tokenAvailable = FileManager.default.ubiquityIdentityToken != nil
            let cloudKitStatus = try? await fetchCloudKitAccountStatus()
            let cloudKitText: String
            switch cloudKitStatus {
            case .available:
                cloudKitText = "CloudKit：已登录"
            case .noAccount:
                cloudKitText = "CloudKit：未登录"
            case .restricted:
                cloudKitText = "CloudKit：受限"
            case .temporarilyUnavailable:
                cloudKitText = "CloudKit：暂时不可用"
            case .couldNotDetermine:
                cloudKitText = "CloudKit：无法确定"
            case .none:
                cloudKitText = "CloudKit：检测失败"
            @unknown default:
                cloudKitText = "CloudKit：未知"
            }

            await MainActor.run {
                let tokenText = tokenAvailable ? "iCloud：已登录" : "iCloud：未登录"
                iCloudStatusMessage = "\(tokenText)；\(cloudKitText)"
            }
        }
    }

    private func fetchCloudKitAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            CKContainer.default().accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func handleCloudKitEventNotification(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        let typeText: String
        switch event.type {
        case .setup:
            typeText = "setup"
        case .import:
            typeText = "import"
        case .export:
            typeText = "export"
        @unknown default:
            typeText = "unknown"
        }

        let successText = event.succeeded ? "成功" : "失败"
        let errorText = event.error.map { "：\($0.localizedDescription)" } ?? ""
        lastCloudKitEventMessage = "最近一次同步事件：\(typeText) \(successText)\(errorText)"
    }

    private func exportData() async {
        await MainActor.run {
            isExporting = true
            exportURL = nil
            isPresentingShare = false
        }

        do {
            let url = try await DataExportService.exportJSON(context: viewContext)
            await MainActor.run {
                exportURL = url
                isPresentingShare = true
                isExporting = false
            }
        } catch {
            await MainActor.run {
                syncResultMessage = "导出失败：\(error.localizedDescription)"
                isExporting = false
            }
        }
    }
}
