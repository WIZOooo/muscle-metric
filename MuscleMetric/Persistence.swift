import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Add some sample data for preview
        let gymTag = TrainingTag(context: viewContext)
        gymTag.id = UUID()
        gymTag.name = "Gold's Gym"
        gymTag.level = 1
        
        let actionTag = TrainingTag(context: viewContext)
        actionTag.id = UUID()
        actionTag.name = "Bench Press"
        actionTag.level = 2
        actionTag.parent = gymTag
        
        let weightTag = TrainingTag(context: viewContext)
        weightTag.id = UUID()
        weightTag.name = "100kg"
        weightTag.level = 3
        weightTag.parent = actionTag
        
        let dietTag = DietTag(context: viewContext)
        dietTag.id = UUID()
        dietTag.name = "Chicken Breast"
        dietTag.calories = 165
        dietTag.protein = 31
        dietTag.fat = 3.6
        dietTag.carbs = 0
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MuscleMetric")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem is.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
