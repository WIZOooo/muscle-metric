import SwiftUI
import CoreData

struct DietRecordListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietRecord.date, ascending: false)],
        animation: .default)
    private var records: FetchedResults<DietRecord>
    
    @State private var showAddSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink(destination: DietRecordDetailView(record: record)) {
                        VStack(alignment: .leading) {
                            Text(record.title ?? "未命名记录")
                                .font(.headline)
                            Text("\(record.date ?? Date(), formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Summary preview
                            HStack(spacing: 10) {
                                Text("🔥 \(Int(totalCalories(for: record)))")
                                Text("P: \(Int(totalProtein(for: record)))")
                            }
                            .font(.caption2)
                            .foregroundColor(.gray)
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("饮食记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDietRecordView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { records[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting diet record: \(error)")
            }
        }
    }
    
    private func totalCalories(for record: DietRecord) -> Double {
        guard let entries = record.entries as? Set<DietEntry> else { return 0 }
        return entries.reduce(0) { $0 + ($1.foodTag?.calories ?? 0) }
    }
    
    private func totalProtein(for record: DietRecord) -> Double {
        guard let entries = record.entries as? Set<DietEntry> else { return 0 }
        return entries.reduce(0) { $0 + ($1.foodTag?.protein ?? 0) }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()
