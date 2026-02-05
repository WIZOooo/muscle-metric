import SwiftUI
import CoreData

struct PersonalInfoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \UserProfile.id, ascending: true)],
        animation: .default)
    private var profiles: FetchedResults<UserProfile>
    
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
                }
                .navigationTitle("个人信息")
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
}
