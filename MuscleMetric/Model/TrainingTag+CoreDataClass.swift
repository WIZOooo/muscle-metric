import Foundation
import CoreData

@objc(TrainingTag)
public class TrainingTag: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var category: String?
    @NSManaged public var level: Int16
    @NSManaged public var parent: TrainingTag?
    @NSManaged public var children: NSSet?
    @NSManaged public var actionEntries: NSSet?
    @NSManaged public var weightEntries: NSSet?
    @NSManaged public var gymRecord: NSSet?
}

extension TrainingTag {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TrainingTag> {
        return NSFetchRequest<TrainingTag>(entityName: "TrainingTag")
    }

    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: TrainingTag)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: TrainingTag)

    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSSet)
    
    @objc(addActionEntriesObject:)
    @NSManaged public func addToActionEntries(_ value: TrainingEntry)

    @objc(removeActionEntriesObject:)
    @NSManaged public func removeFromActionEntries(_ value: TrainingEntry)

    @objc(addActionEntries:)
    @NSManaged public func addToActionEntries(_ values: NSSet)

    @objc(removeActionEntries:)
    @NSManaged public func removeFromActionEntries(_ values: NSSet)

    @objc(addWeightEntriesObject:)
    @NSManaged public func addToWeightEntries(_ value: TrainingEntry)

    @objc(removeWeightEntriesObject:)
    @NSManaged public func removeFromWeightEntries(_ value: TrainingEntry)

    @objc(addWeightEntries:)
    @NSManaged public func addToWeightEntries(_ values: NSSet)

    @objc(removeWeightEntries:)
    @NSManaged public func removeFromWeightEntries(_ values: NSSet)
    
    @objc(addGymRecordObject:)
    @NSManaged public func addToGymRecord(_ value: TrainingRecord)

    @objc(removeGymRecordObject:)
    @NSManaged public func removeFromGymRecord(_ value: TrainingRecord)

    @objc(addGymRecord:)
    @NSManaged public func addToGymRecord(_ values: NSSet)

    @objc(removeGymRecord:)
    @NSManaged public func removeFromGymRecord(_ values: NSSet)
}
