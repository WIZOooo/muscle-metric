import Foundation
import CoreData

@objc(DietRecord)
public class DietRecord: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var title: String?
    @NSManaged public var entries: NSSet?
}

extension DietRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DietRecord> {
        return NSFetchRequest<DietRecord>(entityName: "DietRecord")
    }

    @objc(addEntriesObject:)
    @NSManaged public func addToEntries(_ value: DietEntry)

    @objc(removeEntriesObject:)
    @NSManaged public func removeFromEntries(_ value: DietEntry)

    @objc(addEntries:)
    @NSManaged public func addToEntries(_ values: NSSet)

    @objc(removeEntries:)
    @NSManaged public func removeFromEntries(_ values: NSSet)
}
