import SwiftUI
import UniformTypeIdentifiers

struct TagManagerView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedTab = 0
    @State private var isPresentingExportSelection = false
    @State private var isPresentingShare = false
    @State private var exportURL: URL?

    @State private var isImporting = false
    @State private var isWorking = false

    @State private var isPresentingAlert = false
    @State private var alertMessage: String = ""
    
    var body: some View {
        VStack {
            Picker("Tag Type", selection: $selectedTab) {
                Text("力训标签").tag(0)
                Text("饮食标签").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if selectedTab == 0 {
                TrainingTagListView()
            } else {
                DietTagListView()
            }
        }
        .navigationTitle("标签管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("导出…") {
                        isPresentingExportSelection = true
                    }
                    Button("导入…") {
                        isImporting = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
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
        .sheet(isPresented: $isPresentingExportSelection) {
            if selectedTab == 0 {
                TrainingTagExportSelectionView { selectedIds in
                    exportTrainingTags(selectedIds: selectedIds)
                }
            } else {
                DietTagExportSelectionView { selectedIds in
                    exportDietTags(selectedIds: selectedIds)
                }
            }
        }
        .sheet(isPresented: $isPresentingShare) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importTags(from: url)
            case .failure(let error):
                showAlert(message: error.localizedDescription)
            }
        }
        .alert("提示", isPresented: $isPresentingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func exportTrainingTags(selectedIds: Set<UUID>?) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let url = try await TagImportExportService.exportTrainingTags(from: viewContext, selectedIds: selectedIds)
                exportURL = url
                isPresentingShare = true
            } catch {
                showAlert(message: error.localizedDescription)
            }
        }
    }

    private func exportDietTags(selectedIds: Set<UUID>?) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let url = try await TagImportExportService.exportDietTags(from: viewContext, selectedIds: selectedIds)
                exportURL = url
                isPresentingShare = true
            } catch {
                showAlert(message: error.localizedDescription)
            }
        }
    }

    private func importTags(from url: URL) {
        Task {
            isWorking = true
            defer { isWorking = false }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let expectedKind = selectedTab == 0 ? TagImportExportService.trainingKind : TagImportExportService.dietKind
                let meta = try decodeMeta(from: url)
                guard meta.kind == expectedKind else {
                    showAlert(message: "当前页面为\(selectedTab == 0 ? "力训标签" : "饮食标签")，请选择对应导出文件再导入。")
                    return
                }

                let report = try await TagImportExportService.importTags(from: url, into: viewContext)
                showAlert(message: "导入完成：新增 \(report.inserted)，合并 \(report.merged)，跳过 \(report.skipped)。")
            } catch {
                showAlert(message: error.localizedDescription)
            }
        }
    }

    private func decodeMeta(from url: URL) throws -> TagImportExportService.Meta {
        struct Wrapper: Decodable {
            var meta: TagImportExportService.Meta
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Wrapper.self, from: data).meta
    }

    private func showAlert(message: String) {
        alertMessage = message
        isPresentingAlert = true
    }
}
