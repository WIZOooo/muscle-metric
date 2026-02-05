import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        TabView {
            DietRecordListView()
                .tabItem {
                    Label("饮食", systemImage: "fork.knife")
                }

            TrainingRecordListView()
                .tabItem {
                    Label("力训", systemImage: "dumbbell")
                }
            
            TagManagerView()
                .tabItem {
                    Label("标签管理", systemImage: "tag")
                }
            
            PersonalInfoView()
                .tabItem {
                    Label("个人信息", systemImage: "person.circle")
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
