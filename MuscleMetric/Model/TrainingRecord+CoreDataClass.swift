import Foundation
import CoreData

@objc(TrainingRecord)
public class TrainingRecord: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var title: String?
    @NSManaged public var gymTag: TrainingTag?
    @NSManaged public var entries: NSSet?
}

extension TrainingRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TrainingRecord> {
        return NSFetchRequest<TrainingRecord>(entityName: "TrainingRecord")
    }

    @objc(addEntriesObject:)
    @NSManaged public func addToEntries(_ value: TrainingEntry)

    @objc(removeEntriesObject:)
    @NSManaged public func removeFromEntries(_ value: TrainingEntry)

    @objc(addEntries:)
    @NSManaged public func addToEntries(_ values: NSSet)

    @objc(removeEntries:)
    @NSManaged public func removeFromEntries(_ values: NSSet)
}
