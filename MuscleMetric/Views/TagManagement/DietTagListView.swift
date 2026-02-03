import SwiftUI
import CoreData

struct DietTagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietTag.name, ascending: true)],
        animation: .default)
    private var dietTags: FetchedResults<DietTag>
    
    @State private var showAddSheet = false
    
    var body: some View {
        List {
            ForEach(dietTags) { tag in
                VStack(alignment: .leading) {
                    Text(tag.name ?? "未知食物")
                        .font(.headline)
                    HStack {
                        Text("热量: \(Int(tag.calories))")
                        Text("P: \(Int(tag.protein))")
                        Text("C: \(Int(tag.carbs))")
                        Text("F: \(Int(tag.fat))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddDietTagView()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { dietTags[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct AddDietTagView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("食物名称", text: $name)
                }
                
                Section(header: Text("营养成分 (每份)")) {
                    TextField("总热量 (kcal)", text: $calories)
                        .keyboardType(.decimalPad)
                    TextField("蛋白质 (g)", text: $protein)
                        .keyboardType(.decimalPad)
                    TextField("碳水化合物 (g)", text: $carbs)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 (g)", text: $fat)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("添加饮食标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        addItem()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addItem() {
        withAnimation {
            let newTag = DietTag(context: viewContext)
            newTag.id = UUID()
            newTag.name = name
            newTag.calories = Double(calories) ?? 0
            newTag.protein = Double(protein) ?? 0
            newTag.carbs = Double(carbs) ?? 0
            newTag.fat = Double(fat) ?? 0
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
