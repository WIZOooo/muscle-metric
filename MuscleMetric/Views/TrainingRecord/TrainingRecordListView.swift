import SwiftUI
import CoreData

struct TrainingRecordListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TrainingRecord.timestamp, ascending: false)],
        animation: .default)
    private var records: FetchedResults<TrainingRecord>
    
    @State private var showAddSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink(destination: TrainingRecordDetailView(record: record)) {
                        VStack(alignment: .leading) {
                            Text(record.title ?? "未命名训练")
                                .font(.headline)
                            Text("\(record.timestamp ?? Date(), formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let gym = record.gymTag {
                                Text("门店: \(gym.name ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("力训记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddTrainingRecordView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { records[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()
