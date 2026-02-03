import SwiftUI

struct TagManagerView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
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
        }
    }
}
