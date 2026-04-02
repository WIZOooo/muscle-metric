import Foundation
import CoreData

@objc(TrainingEntry)
public class TrainingEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var exerciseName: String?
    @NSManaged public var orderIndex: Int32
    @NSManaged public var planRep: String?
    @NSManaged public var planRest: String?
    @NSManaged public var planTargetSet: Int16
    @NSManaged public var planFinishedSet: Int16
    @NSManaged public var maxWeight: String?
    @NSManaged public var notes: String?
    @NSManaged public var actionTag: TrainingTag?
    @NSManaged public var weightTag: TrainingTag?
    @NSManaged public var record: TrainingRecord?
}

extension TrainingEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TrainingEntry> {
        return NSFetchRequest<TrainingEntry>(entityName: "TrainingEntry")
    }
}
