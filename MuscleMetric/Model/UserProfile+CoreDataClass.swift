import Foundation
import CoreData

@objc(UserProfile)
public class UserProfile: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var age: Int16
    @NSManaged public var gender: String?
    @NSManaged public var goal: String?
    @NSManaged public var height: Double
    @NSManaged public var weight: Double
}

extension UserProfile {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfile> {
        return NSFetchRequest<UserProfile>(entityName: "UserProfile")
    }
}
