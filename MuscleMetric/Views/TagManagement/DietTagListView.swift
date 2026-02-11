import SwiftUI
import CoreData

struct DietTagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DietTag.name, ascending: true)],
        animation: .default)
    private var dietTags: FetchedResults<DietTag>
    
    @State private var showAddSheet = false
    @State private var editingTag: DietTag?
    @State private var searchText = ""
    @State private var isSearchFieldPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredTags: [DietTag] {
        let all = Array(dietTags)
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        return all.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        List {
            ForEach(filteredTags) { tag in
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text(tag.name ?? "未知食物")
                            .font(.headline)
                        HStack {
                            Text("热量: \(Int(tag.calories))")
                            Text("蛋白质: \(Int(tag.protein))")
                            Text("碳水: \(Int(tag.carbs))")
                            Text("脂肪: \(Int(tag.fat))")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        editingTag = tag
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                deleteItems(tags: filteredTags, offsets: offsets)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    if isSearchFieldPresented {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isSearchFieldPresented = false
                        }
                        isSearchFieldFocused = false
                    }
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSearchFieldPresented {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索食物", text: $searchText)
                            .focused($isSearchFieldFocused)
                            .submitLabel(.search)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .onSubmit {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isSearchFieldPresented = false
                        }
                        isSearchFieldFocused = false
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isSearchFieldPresented.toggle()
                    }
                    if isSearchFieldPresented {
                        DispatchQueue.main.async {
                            isSearchFieldFocused = true
                        }
                    } else {
                        isSearchFieldFocused = false
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Label("添加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddDietTagView()
        }
        .sheet(item: $editingTag) { tag in
            EditDietTagView(tag: tag)
        }
    }

    private func deleteItems(tags: [DietTag], offsets: IndexSet) {
        withAnimation {
            offsets.map { tags[$0] }.forEach(viewContext.delete)
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

struct EditDietTagView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tag: DietTag

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
            .navigationTitle("编辑饮食标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = tag.name ?? ""
                calories = String(format: "%.1f", tag.calories)
                protein = String(format: "%.1f", tag.protein)
                carbs = String(format: "%.1f", tag.carbs)
                fat = String(format: "%.1f", tag.fat)
            }
        }
    }

    private func save() {
        withAnimation {
            tag.name = name
            tag.calories = Double(calories) ?? 0
            tag.protein = Double(protein) ?? 0
            tag.carbs = Double(carbs) ?? 0
            tag.fat = Double(fat) ?? 0

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
