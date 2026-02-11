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
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
                let containerIdentifier = "iCloud.\(bundleIdentifier)"
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                print("[CloudKit] bundleIdentifier=\(bundleIdentifier)")
                print("[CloudKit] containerIdentifier=\(containerIdentifier)")
            } else {
                print("[CloudKit] bundleIdentifier missing; CloudKit container not explicitly configured")
            }

            if let storeURL = description.url {
                print("[CoreData] storeURL=\(storeURL.path)")
            }

            if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
                print("[InfoPlist] UIBackgroundModes=\(backgroundModes)")
            } else {
                print("[InfoPlist] UIBackgroundModes missing")
            }
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

            if let containerIdentifier = storeDescription.cloudKitContainerOptions?.containerIdentifier {
                print("[CloudKit] storeLoaded containerIdentifier=\(containerIdentifier)")
            } else {
                print("[CloudKit] storeLoaded without cloudKitContainerOptions (likely iCloud/CloudKit capability missing)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true

        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: nil) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            let typeText: String
            switch event.type {
            case .setup:
                typeText = "setup"
            case .import:
                typeText = "import"
            case .export:
                typeText = "export"
            @unknown default:
                typeText = "unknown"
            }

            let successText = event.succeeded ? "success" : "failure"
            if let error = event.error {
                print("[CloudKitEvent] type=\(typeText) \(successText) error=\(error)")
            } else {
                print("[CloudKitEvent] type=\(typeText) \(successText)")
            }
        }
    }
}

struct SyncReport: Sendable {
    var normalizedIds: [String: Int] = [:]
    var mergedById: [String: Int] = [:]
    var mergedBySemanticKey: [String: Int] = [:]
    var deletedDuplicates: [String: Int] = [:]

    var normalizedIdsTotal: Int { normalizedIds.values.reduce(0, +) }
    var mergedByIdTotal: Int { mergedById.values.reduce(0, +) }
    var mergedBySemanticKeyTotal: Int { mergedBySemanticKey.values.reduce(0, +) }
    var deletedDuplicatesTotal: Int { deletedDuplicates.values.reduce(0, +) }
}

enum CloudManualSyncError: Error {
    case missingPersistentStore
}

struct CloudManualSyncService {
    static func manualSync(container: NSPersistentCloudKitContainer) async throws -> SyncReport {
        try await container.viewContext.performAsync {
            if container.viewContext.hasChanges {
                try container.viewContext.save()
            }
        }

        let report = try await container.performBackgroundTaskAsync { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil
            var report = SyncReport()
            try CoreDataDeduplicator.reconcileAll(in: context, report: &report)
            if context.hasChanges {
                try context.save()
            }
            return report
        }

        try await container.viewContext.performAsync {
            container.viewContext.refreshAllObjects()
            if container.viewContext.hasChanges {
                try container.viewContext.save()
            }
        }

        return report
    }
}

struct CoreDataDeduplicator {
    static func reconcileAll(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        try normalizeMissingIds(in: context, report: &report)

        try mergeUserProfiles(in: context, report: &report)

        try dedupeTrainingTags(in: context, report: &report)
        try dedupeDietTags(in: context, report: &report)

        try dedupeTrainingRecords(in: context, report: &report)
        try dedupeDietRecords(in: context, report: &report)

        try dedupeTrainingEntries(in: context, report: &report)
        try dedupeDietEntries(in: context, report: &report)
    }

    private static func normalizeMissingIds(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        try normalizeMissingIds(entityName: "TrainingTag", in: context, report: &report)
        try normalizeMissingIds(entityName: "DietTag", in: context, report: &report)
        try normalizeMissingIds(entityName: "TrainingRecord", in: context, report: &report)
        try normalizeMissingIds(entityName: "DietRecord", in: context, report: &report)
        try normalizeMissingIds(entityName: "TrainingEntry", in: context, report: &report)
        try normalizeMissingIds(entityName: "DietEntry", in: context, report: &report)
        try normalizeMissingIds(entityName: "UserProfile", in: context, report: &report)
    }

    private static func normalizeMissingIds(entityName: String, in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let objects = try context.fetch(request)
        var updatedCount = 0
        for object in objects {
            if (object.value(forKey: "id") as? UUID) == nil {
                object.setValue(UUID(), forKey: "id")
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            report.normalizedIds[entityName, default: 0] += updatedCount
        }
    }

    private static func mergeUserProfiles(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<UserProfile>(entityName: "UserProfile")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let profiles = try context.fetch(request)
        guard profiles.count > 1 else { return }

        let canonical = profiles.max(by: { score($0) < score($1) }) ?? profiles[0]
        for other in profiles where other != canonical {
            mergeUserProfile(from: other, into: canonical)
            context.delete(other)
            report.deletedDuplicates["UserProfile", default: 0] += 1
            report.mergedBySemanticKey["UserProfile", default: 0] += 1
        }
    }

    private static func dedupeTrainingTags(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<TrainingTag>(entityName: "TrainingTag")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let tags = try context.fetch(request)
        try dedupeById(tags: tags, entityName: "TrainingTag", report: &report) { canonical, other in
            mergeTrainingTag(from: other, into: canonical)
            reassignTrainingTagReferences(from: other, to: canonical)
        }

        let byKey = Dictionary(grouping: try context.fetch(request), by: { trainingTagSemanticKey($0) })
        for (_, group) in byKey where group.count > 1 {
            let canonical = group.max(by: { score($0) < score($1) }) ?? group[0]
            for other in group where other != canonical {
                mergeTrainingTag(from: other, into: canonical)
                reassignTrainingTagReferences(from: other, to: canonical)
                context.delete(other)
                report.deletedDuplicates["TrainingTag", default: 0] += 1
                report.mergedBySemanticKey["TrainingTag", default: 0] += 1
            }
        }
    }

    private static func dedupeDietTags(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<DietTag>(entityName: "DietTag")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let tags = try context.fetch(request)
        try dedupeById(tags: tags, entityName: "DietTag", report: &report) { canonical, other in
            mergeDietTag(from: other, into: canonical)
            reassignDietTagReferences(from: other, to: canonical)
        }

        let byName = Dictionary(grouping: try context.fetch(request), by: { dietTagSemanticKey($0) })
        for (_, group) in byName where group.count > 1 {
            let canonical = group.max(by: { score($0) < score($1) }) ?? group[0]
            for other in group where other != canonical {
                mergeDietTag(from: other, into: canonical)
                reassignDietTagReferences(from: other, to: canonical)
                context.delete(other)
                report.deletedDuplicates["DietTag", default: 0] += 1
                report.mergedBySemanticKey["DietTag", default: 0] += 1
            }
        }
    }

    private static func dedupeTrainingRecords(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<TrainingRecord>(entityName: "TrainingRecord")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let records = try context.fetch(request)
        try dedupeById(tags: records, entityName: "TrainingRecord", report: &report) { canonical, other in
            mergeTrainingRecord(from: other, into: canonical)
        }
    }

    private static func dedupeDietRecords(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<DietRecord>(entityName: "DietRecord")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let records = try context.fetch(request)
        try dedupeById(tags: records, entityName: "DietRecord", report: &report) { canonical, other in
            mergeDietRecord(from: other, into: canonical)
        }
    }

    private static func dedupeTrainingEntries(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<TrainingEntry>(entityName: "TrainingEntry")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let entries = try context.fetch(request)
        try dedupeById(tags: entries, entityName: "TrainingEntry", report: &report) { canonical, other in
            mergeTrainingEntry(from: other, into: canonical)
        }
    }

    private static func dedupeDietEntries(in context: NSManagedObjectContext, report: inout SyncReport) throws {
        let request = NSFetchRequest<DietEntry>(entityName: "DietEntry")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true

        let entries = try context.fetch(request)
        try dedupeById(tags: entries, entityName: "DietEntry", report: &report) { canonical, other in
            mergeDietEntry(from: other, into: canonical)
        }
    }

    private static func dedupeById<T: NSManagedObject & Identifiable>(tags: [T], entityName: String, report: inout SyncReport, merge: (T, T) -> Void) throws {
        var byId: [UUID: [T]] = [:]
        for obj in tags {
            guard let id = obj.value(forKey: "id") as? UUID else { continue }
            byId[id, default: []].append(obj)
        }

        for (_, group) in byId where group.count > 1 {
            let canonical = group.max(by: { score($0) < score($1) }) ?? group[0]
            for other in group where other != canonical {
                merge(canonical, other)
                other.managedObjectContext?.delete(other)
                report.deletedDuplicates[entityName, default: 0] += 1
                report.mergedById[entityName, default: 0] += 1
            }
        }
    }

    private static func mergeUserProfile(from other: UserProfile, into canonical: UserProfile) {
        if canonical.age == 0, other.age > 0 { canonical.age = other.age }
        if (canonical.gender ?? "").isEmpty, let v = other.gender, !v.isEmpty { canonical.gender = v }
        if (canonical.goal ?? "").isEmpty, let v = other.goal, !v.isEmpty { canonical.goal = v }
        if canonical.height == 0, other.height > 0 { canonical.height = other.height }
        if canonical.weight == 0, other.weight > 0 { canonical.weight = other.weight }
    }

    private static func mergeTrainingTag(from other: TrainingTag, into canonical: TrainingTag) {
        if (canonical.name ?? "").isEmpty, let v = other.name, !v.isEmpty { canonical.name = v }
        if (canonical.category ?? "").isEmpty, let v = other.category, !v.isEmpty { canonical.category = v }
        if canonical.level == 0, other.level != 0 { canonical.level = other.level }
        if canonical.parent == nil, let p = other.parent { canonical.parent = p }

        if let children = other.children as? Set<TrainingTag> {
            for child in children {
                child.parent = canonical
            }
        }
    }

    private static func reassignTrainingTagReferences(from other: TrainingTag, to canonical: TrainingTag) {
        if let actionEntries = other.actionEntries as? Set<TrainingEntry> {
            for entry in actionEntries {
                entry.actionTag = canonical
            }
        }

        if let weightEntries = other.weightEntries as? Set<TrainingEntry> {
            for entry in weightEntries {
                entry.weightTag = canonical
            }
        }

        if let gymRecords = other.gymRecord as? Set<TrainingRecord> {
            for record in gymRecords {
                record.gymTag = canonical
            }
        }
    }

    private static func mergeDietTag(from other: DietTag, into canonical: DietTag) {
        if (canonical.name ?? "").isEmpty, let v = other.name, !v.isEmpty { canonical.name = v }
        if canonical.calories == 0, other.calories > 0 { canonical.calories = other.calories }
        if canonical.protein == 0, other.protein > 0 { canonical.protein = other.protein }
        if canonical.fat == 0, other.fat > 0 { canonical.fat = other.fat }
        if canonical.carbs == 0, other.carbs > 0 { canonical.carbs = other.carbs }
    }

    private static func reassignDietTagReferences(from other: DietTag, to canonical: DietTag) {
        if let entries = other.entries as? Set<DietEntry> {
            for entry in entries {
                entry.foodTag = canonical
            }
        }
    }

    private static func mergeTrainingRecord(from other: TrainingRecord, into canonical: TrainingRecord) {
        if canonical.timestamp == nil, let v = other.timestamp { canonical.timestamp = v }
        if (canonical.title ?? "").isEmpty, let v = other.title, !v.isEmpty { canonical.title = v }
        if canonical.gymTag == nil, let v = other.gymTag { canonical.gymTag = v }

        if let entries = other.entries as? Set<TrainingEntry> {
            for entry in entries {
                entry.record = canonical
            }
        }
    }

    private static func mergeDietRecord(from other: DietRecord, into canonical: DietRecord) {
        if canonical.date == nil, let v = other.date { canonical.date = v }
        if (canonical.title ?? "").isEmpty, let v = other.title, !v.isEmpty { canonical.title = v }
        if canonical.activeEnergy == 0, other.activeEnergy > 0 { canonical.activeEnergy = other.activeEnergy }

        if let entries = other.entries as? Set<DietEntry> {
            for entry in entries {
                entry.record = canonical
            }
        }
    }

    private static func mergeTrainingEntry(from other: TrainingEntry, into canonical: TrainingEntry) {
        if canonical.orderIndex == 0, other.orderIndex != 0 { canonical.orderIndex = other.orderIndex }
        if canonical.actionTag == nil, let v = other.actionTag { canonical.actionTag = v }
        if canonical.weightTag == nil, let v = other.weightTag { canonical.weightTag = v }
        if canonical.record == nil, let v = other.record { canonical.record = v }
    }

    private static func mergeDietEntry(from other: DietEntry, into canonical: DietEntry) {
        if canonical.orderIndex == 0, other.orderIndex != 0 { canonical.orderIndex = other.orderIndex }
        if canonical.portion == 1.0, other.portion != 1.0 { canonical.portion = other.portion }
        if canonical.foodTag == nil, let v = other.foodTag { canonical.foodTag = v }
        if canonical.record == nil, let v = other.record { canonical.record = v }
    }

    private static func score(_ obj: NSManagedObject) -> Int {
        let entityName = obj.entity.name ?? ""
        switch entityName {
        case "UserProfile":
            guard let p = obj as? UserProfile else { return 0 }
            var s = 0
            if p.age > 0 { s += 1 }
            if !(p.gender ?? "").isEmpty { s += 1 }
            if !(p.goal ?? "").isEmpty { s += 1 }
            if p.height > 0 { s += 1 }
            if p.weight > 0 { s += 1 }
            return s
        case "TrainingTag":
            guard let t = obj as? TrainingTag else { return 0 }
            var s = 0
            if !(t.name ?? "").isEmpty { s += 1 }
            if !(t.category ?? "").isEmpty { s += 1 }
            if t.level != 0 { s += 1 }
            if t.parent != nil { s += 1 }
            if (t.children as? Set<TrainingTag>)?.isEmpty == false { s += 1 }
            return s
        case "DietTag":
            guard let t = obj as? DietTag else { return 0 }
            var s = 0
            if !(t.name ?? "").isEmpty { s += 1 }
            if t.calories > 0 { s += 1 }
            if t.protein > 0 { s += 1 }
            if t.fat > 0 { s += 1 }
            if t.carbs > 0 { s += 1 }
            return s
        case "TrainingRecord":
            guard let r = obj as? TrainingRecord else { return 0 }
            var s = 0
            if r.timestamp != nil { s += 1 }
            if !(r.title ?? "").isEmpty { s += 1 }
            if r.gymTag != nil { s += 1 }
            if (r.entries as? Set<TrainingEntry>)?.isEmpty == false { s += 1 }
            return s
        case "DietRecord":
            guard let r = obj as? DietRecord else { return 0 }
            var s = 0
            if r.date != nil { s += 1 }
            if !(r.title ?? "").isEmpty { s += 1 }
            if r.activeEnergy > 0 { s += 1 }
            if (r.entries as? Set<DietEntry>)?.isEmpty == false { s += 1 }
            return s
        case "TrainingEntry":
            guard let e = obj as? TrainingEntry else { return 0 }
            var s = 0
            if e.orderIndex != 0 { s += 1 }
            if e.actionTag != nil { s += 1 }
            if e.weightTag != nil { s += 1 }
            if e.record != nil { s += 1 }
            return s
        case "DietEntry":
            guard let e = obj as? DietEntry else { return 0 }
            var s = 0
            if e.orderIndex != 0 { s += 1 }
            if e.portion != 1.0 { s += 1 }
            if e.foodTag != nil { s += 1 }
            if e.record != nil { s += 1 }
            return s
        default:
            return 0
        }
    }

    private static func trainingTagSemanticKey(_ tag: TrainingTag) -> String {
        let name = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let level = "\(tag.level)"
        let parentId = (tag.parent?.id?.uuidString) ?? ""
        let parentName = (tag.parent?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tag.level <= 1 {
            return "\(level)|\(name)"
        }
        if !parentId.isEmpty {
            return "\(level)|\(parentId)|\(name)"
        }
        return "\(level)|\(parentName)|\(name)"
    }

    private static func dietTagSemanticKey(_ tag: DietTag) -> String {
        (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension NSPersistentCloudKitContainer {
    func performBackgroundTaskAsync<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.performBackgroundTask { context in
                do {
                    let value = try block(context)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension NSManagedObjectContext {
    func performAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.perform {
                do {
                    let value = try block()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
