import Foundation
import CoreData

@objc(BodyMeasurement)
public class BodyMeasurement: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var weightKg: Double
    @NSManaged public var bodyFatPercent: Double
    @NSManaged public var impedance: Int32
    @NSManaged public var heartRate: Int16
    @NSManaged public var deviceId: String?
    @NSManaged public var deviceName: String?
    @NSManaged public var source: String?
}

extension BodyMeasurement {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BodyMeasurement> {
        NSFetchRequest<BodyMeasurement>(entityName: "BodyMeasurement")
    }
}

