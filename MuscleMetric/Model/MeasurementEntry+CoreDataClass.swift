import Foundation
import CoreData

@objc(MeasurementEntry)
public class MeasurementEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var note: String?

    @NSManaged public var weightKg: Double
    @NSManaged public var bodyFatPercent: Double
    @NSManaged public var leanBodyMassKg: Double

    @NSManaged public var chestCm: Double
    @NSManaged public var waistCm: Double
    @NSManaged public var hipCm: Double
    @NSManaged public var shoulderWidthCm: Double

    @NSManaged public var armLeftCm: Double
    @NSManaged public var armRightCm: Double
    @NSManaged public var thighLeftCm: Double
    @NSManaged public var thighRightCm: Double
    @NSManaged public var calfLeftCm: Double
    @NSManaged public var calfRightCm: Double
}

extension MeasurementEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MeasurementEntry> {
        NSFetchRequest<MeasurementEntry>(entityName: "MeasurementEntry")
    }
}
