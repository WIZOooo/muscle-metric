import Foundation
import CoreData

@objc(DietEntry)
public class DietEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var orderIndex: Int32
    @NSManaged public var portion: Double
    @NSManaged public var foodTag: DietTag?
    @NSManaged public var record: DietRecord?
}

extension DietEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DietEntry> {
        return NSFetchRequest<DietEntry>(entityName: "DietEntry")
    }
}
