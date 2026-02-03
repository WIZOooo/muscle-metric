import Foundation
import CoreData

@objc(TrainingEntry)
public class TrainingEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var orderIndex: Int32
    @NSManaged public var actionTag: TrainingTag?
    @NSManaged public var weightTag: TrainingTag?
    @NSManaged public var record: TrainingRecord?
}

extension TrainingEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TrainingEntry> {
        return NSFetchRequest<TrainingEntry>(entityName: "TrainingEntry")
    }
}
