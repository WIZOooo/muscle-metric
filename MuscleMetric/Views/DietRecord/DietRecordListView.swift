import SwiftUI
import CoreData

struct DietRecordListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietRecord.date, ascending: false)],
        animation: .default)
    private var records: FetchedResults<DietRecord>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UserProfile.id, ascending: true)],
        animation: .default)
    private var userProfiles: FetchedResults<UserProfile>
    
    private var userProfile: UserProfile? { userProfiles.first }
    
    private var bmr: Double {
        guard let weight = userProfile?.weight, weight > 0 else { return 0 }
        return weight * 24
    }
    
    @State private var showAddSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink(destination: DietRecordDetailView(record: record)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(record.date ?? Date(), formatter: headerDateFormatter) 饮食概况")
                                .font(.headline)
                            
                            // Summary preview
                            HStack(spacing: 10) {
                                let deficit = calorieDeficit(for: record)
                                HStack(spacing: 2) {
                                    Text("热量缺口: ")
                                    Text("\(Int(deficit))")
                                        .foregroundColor(deficit >= 0 ? .green : .red)
                                }
                                Text("蛋白质: \(Int(totalProtein(for: record)))")
                                Text("脂肪: \(Int(totalFat(for: record)))")
                                Text("碳水: \(Int(totalCarbs(for: record)))")
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
        .onAppear {
            for record in records.prefix(5) {
                viewContext.refresh(record, mergeChanges: true)
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
        return entries.reduce(0) { total, entry in
            let portion = entry.portion == 0 ? 1.0 : entry.portion
            return total + (entry.foodTag?.calories ?? 0) * portion
        }
    }
    
    private func totalProtein(for record: DietRecord) -> Double {
        guard let entries = record.entries as? Set<DietEntry> else { return 0 }
        return entries.reduce(0) { total, entry in
            let portion = entry.portion == 0 ? 1.0 : entry.portion
            return total + (entry.foodTag?.protein ?? 0) * portion
        }
    }

    private func totalFat(for record: DietRecord) -> Double {
        guard let entries = record.entries as? Set<DietEntry> else { return 0 }
        return entries.reduce(0) { total, entry in
            let portion = entry.portion == 0 ? 1.0 : entry.portion
            return total + (entry.foodTag?.fat ?? 0) * portion
        }
    }

    private func totalCarbs(for record: DietRecord) -> Double {
        guard let entries = record.entries as? Set<DietEntry> else { return 0 }
        return entries.reduce(0) { total, entry in
            let portion = entry.portion == 0 ? 1.0 : entry.portion
            return total + (entry.foodTag?.carbs ?? 0) * portion
        }
    }

    private func calorieDeficit(for record: DietRecord) -> Double {
        let totalCal = totalCalories(for: record)
        return (bmr + record.activeEnergy) - totalCal
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

private let headerDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter
}()
