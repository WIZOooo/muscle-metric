import Foundation
import CoreData

@objc(DietTag)
public class DietTag: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var calories: Double
    @NSManaged public var protein: Double
    @NSManaged public var fat: Double
    @NSManaged public var carbs: Double
    @NSManaged public var entries: NSSet?
}

extension DietTag {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DietTag> {
        return NSFetchRequest<DietTag>(entityName: "DietTag")
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
