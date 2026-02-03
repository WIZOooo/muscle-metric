import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        TabView {
            TrainingRecordListView()
                .tabItem {
                    Label("力训", systemImage: "dumbbell")
                }
            
            DietRecordListView()
                .tabItem {
                    Label("饮食", systemImage: "fork.knife")
                }
            
            TagManagerView()
                .tabItem {
                    Label("标签管理", systemImage: "tag")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
