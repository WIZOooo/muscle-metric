import Foundation
import CoreData

enum DataExportService {
    static func exportJSON(context: NSManagedObjectContext) async throws -> URL {
        let payload = try await context.perform {
            try buildPayload(context: context)
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = "MuscleMetric-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func buildPayload(context: NSManagedObjectContext) throws -> [String: Any] {
        let profiles = try context.fetch(UserProfile.fetchRequest())
        let dietTags = try context.fetch(DietTag.fetchRequest())
        let dietRecords = try context.fetch(DietRecord.fetchRequest())
        let dietEntries = try context.fetch(DietEntry.fetchRequest())
        let trainingTags = try context.fetch(TrainingTag.fetchRequest())
        let trainingRecords = try context.fetch(TrainingRecord.fetchRequest())
        let trainingEntries = try context.fetch(TrainingEntry.fetchRequest())

        return [
            "meta": [
                "exportedAt": iso8601(Date()),
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "storeType": "CoreData+CloudKit",
            ],
            "userProfiles": profiles.map(encode),
            "dietTags": dietTags.map(encode),
            "dietRecords": dietRecords.map(encode),
            "dietEntries": dietEntries.map(encode),
            "trainingTags": trainingTags.map(encode),
            "trainingRecords": trainingRecords.map(encode),
            "trainingEntries": trainingEntries.map(encode),
        ]
    }

    private static func encode(_ profile: UserProfile) -> [String: Any] {
        [
            "id": uuidString(profile.id),
            "age": Int(profile.age),
            "gender": profile.gender ?? "",
            "goal": profile.goal ?? "",
            "height": profile.height,
            "weight": profile.weight,
        ]
    }

    private static func encode(_ tag: DietTag) -> [String: Any] {
        [
            "id": uuidString(tag.id),
            "name": tag.name ?? "",
            "calories": tag.calories,
            "protein": tag.protein,
            "fat": tag.fat,
            "carbs": tag.carbs,
        ]
    }

    private static func encode(_ record: DietRecord) -> [String: Any] {
        [
            "id": uuidString(record.id),
            "date": iso8601(record.date),
            "title": record.title ?? "",
            "activeEnergy": record.activeEnergy,
            "entryIds": (record.entries as? Set<DietEntry>)?.sorted(by: { ($0.orderIndex, uuidString($0.id)) < ($1.orderIndex, uuidString($1.id)) }).map { uuidString($0.id) } ?? [],
        ]
    }

    private static func encode(_ entry: DietEntry) -> [String: Any] {
        [
            "id": uuidString(entry.id),
            "orderIndex": Int(entry.orderIndex),
            "portion": entry.portion,
            "recordId": uuidString(entry.record?.id),
            "foodTagId": uuidString(entry.foodTag?.id),
        ]
    }

    private static func encode(_ tag: TrainingTag) -> [String: Any] {
        [
            "id": uuidString(tag.id),
            "name": tag.name ?? "",
            "category": tag.category ?? "",
            "level": Int(tag.level),
            "parentId": uuidString(tag.parent?.id),
            "childrenIds": (tag.children as? Set<TrainingTag>)?.map { uuidString($0.id) }.sorted() ?? [],
        ]
    }

    private static func encode(_ record: TrainingRecord) -> [String: Any] {
        [
            "id": uuidString(record.id),
            "timestamp": iso8601(record.timestamp),
            "title": record.title ?? "",
            "gymTagId": uuidString(record.gymTag?.id),
            "entryIds": (record.entries as? Set<TrainingEntry>)?.sorted(by: { ($0.orderIndex, uuidString($0.id)) < ($1.orderIndex, uuidString($1.id)) }).map { uuidString($0.id) } ?? [],
        ]
    }

    private static func encode(_ entry: TrainingEntry) -> [String: Any] {
        [
            "id": uuidString(entry.id),
            "orderIndex": Int(entry.orderIndex),
            "recordId": uuidString(entry.record?.id),
            "actionTagId": uuidString(entry.actionTag?.id),
            "weightTagId": uuidString(entry.weightTag?.id),
        ]
    }

    private static func uuidString(_ uuid: UUID?) -> String {
        uuid?.uuidString ?? ""
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
