//
//  MuscleMetricTests.swift
//  MuscleMetricTests
//
//  Created by iMac on 2026/1/30.
//

import XCTest
import CoreData
@testable import MuscleMetric

final class MuscleMetricTests: XCTestCase {

    func testUserProfileMergesToSingleObject() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext

        context.performAndWait {
            let p1 = UserProfile(context: context)
            p1.id = UUID()
            p1.age = 0
            p1.gender = ""
            p1.goal = ""
            p1.height = 0
            p1.weight = 0

            let p2 = UserProfile(context: context)
            p2.id = UUID()
            p2.age = 31
            p2.gender = "女"
            p2.goal = "减脂"
            p2.height = 165
            p2.weight = 55
        }

        try context.performAndWaitThrowing {
            var report = SyncReport()
            try CoreDataDeduplicator.reconcileAll(in: context, report: &report)
            try context.save()
        }

        let profiles = try context.fetch(NSFetchRequest<UserProfile>(entityName: "UserProfile"))
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].age, 31)
        XCTAssertEqual(profiles[0].gender, "女")
        XCTAssertEqual(profiles[0].goal, "减脂")
        XCTAssertEqual(profiles[0].height, 165)
        XCTAssertEqual(profiles[0].weight, 55)
    }

    func testDietTagSemanticDedupReassignsEntries() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext

        let recordId = UUID()
        let tagAId = UUID()
        let tagBId = UUID()

        context.performAndWait {
            let record = DietRecord(context: context)
            record.id = recordId
            record.date = Date()
            record.title = "早餐"

            let tagA = DietTag(context: context)
            tagA.id = tagAId
            tagA.name = "鸡胸肉"
            tagA.protein = 31

            let tagB = DietTag(context: context)
            tagB.id = tagBId
            tagB.name = "  鸡胸肉 "
            tagB.protein = 0

            let entry = DietEntry(context: context)
            entry.id = UUID()
            entry.orderIndex = 0
            entry.portion = 1
            entry.record = record
            entry.foodTag = tagB
        }

        try context.performAndWaitThrowing {
            var report = SyncReport()
            try CoreDataDeduplicator.reconcileAll(in: context, report: &report)
            try context.save()
        }

        let tags = try context.fetch(NSFetchRequest<DietTag>(entityName: "DietTag"))
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name?.trimmingCharacters(in: .whitespacesAndNewlines), "鸡胸肉")
        XCTAssertEqual(tags[0].protein, 31)

        let entries = try context.fetch(NSFetchRequest<DietEntry>(entityName: "DietEntry"))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].foodTag?.objectID, tags[0].objectID)
    }

    func testDietTagExportImportRoundTrip() async throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext

        let chickenId = UUID()
        let bananaId = UUID()

        try context.performAndWaitThrowing {
            let chicken = DietTag(context: context)
            chicken.id = chickenId
            chicken.name = "鸡胸肉"
            chicken.calories = 165
            chicken.protein = 31
            chicken.fat = 3.6
            chicken.carbs = 0

            let banana = DietTag(context: context)
            banana.id = bananaId
            banana.name = "香蕉"
            banana.calories = 89
            banana.protein = 1.1
            banana.fat = 0.3
            banana.carbs = 23

            try context.save()
        }

        let exportURL = try await TagImportExportService.exportDietTags(from: context, selectedIds: nil)

        let importContainer = try makeInMemoryContainer()
        let importContext = importContainer.viewContext
        let report = try await TagImportExportService.importTags(from: exportURL, into: importContext)
        XCTAssertEqual(report.inserted, 2)

        let imported = try importContext.fetch(NSFetchRequest<DietTag>(entityName: "DietTag"))
        XCTAssertEqual(imported.count, 2)
        XCTAssertNotNil(imported.first(where: { ($0.name ?? "") == "鸡胸肉" }))
        XCTAssertNotNil(imported.first(where: { ($0.name ?? "") == "香蕉" }))
    }

    func testDietTagImportMergesByNameWithoutOverwriting() async throws {
        let baseContainer = try makeInMemoryContainer()
        let baseContext = baseContainer.viewContext

        let exportId = UUID()
        try baseContext.performAndWaitThrowing {
            let chicken = DietTag(context: baseContext)
            chicken.id = exportId
            chicken.name = "鸡胸肉"
            chicken.calories = 0
            chicken.protein = 31
            chicken.fat = 0
            chicken.carbs = 0
            try baseContext.save()
        }

        let exportURL = try await TagImportExportService.exportDietTags(from: baseContext, selectedIds: nil)

        let importContainer = try makeInMemoryContainer()
        let importContext = importContainer.viewContext

        try importContext.performAndWaitThrowing {
            let existing = DietTag(context: importContext)
            existing.id = UUID()
            existing.name = "  鸡胸肉  "
            existing.calories = 100
            existing.protein = 0
            existing.fat = 0
            existing.carbs = 0
            try importContext.save()
        }

        let report = try await TagImportExportService.importTags(from: exportURL, into: importContext)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertEqual(report.merged, 1)

        let tags = try importContext.fetch(NSFetchRequest<DietTag>(entityName: "DietTag"))
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].calories, 100)
        XCTAssertEqual(tags[0].protein, 31)
    }

    func testTrainingTagExportSelectionClosureIncludesAncestorsAndDescendants() async throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext

        let gymId = UUID()
        let actionId = UUID()
        let weightId = UUID()

        try context.performAndWaitThrowing {
            let gym = TrainingTag(context: context)
            gym.id = gymId
            gym.level = 1
            gym.name = "门店A"

            let action = TrainingTag(context: context)
            action.id = actionId
            action.level = 2
            action.name = "卧推"
            action.category = "胸"
            action.parent = gym

            let weight = TrainingTag(context: context)
            weight.id = weightId
            weight.level = 3
            weight.name = "60kg"
            weight.parent = action

            try context.save()
        }

        let exportURL = try await TagImportExportService.exportTrainingTags(from: context, selectedIds: [actionId])

        let importContainer = try makeInMemoryContainer()
        let importContext = importContainer.viewContext
        let report = try await TagImportExportService.importTags(from: exportURL, into: importContext)
        XCTAssertEqual(report.inserted, 3)

        let tags = try importContext.fetch(NSFetchRequest<TrainingTag>(entityName: "TrainingTag"))
        XCTAssertEqual(tags.count, 3)

        let gym = tags.first(where: { $0.level == 1 && ($0.name ?? "") == "门店A" })
        let action = tags.first(where: { $0.level == 2 && ($0.name ?? "") == "卧推" })
        let weight = tags.first(where: { $0.level == 3 && ($0.name ?? "") == "60kg" })
        XCTAssertNotNil(gym)
        XCTAssertNotNil(action)
        XCTAssertNotNil(weight)
        XCTAssertEqual(action?.parent?.name, gym?.name)
        XCTAssertEqual(weight?.parent?.name, action?.name)
    }

    func testBodyMeasurementSemanticDedupMergesFields() throws {
        let container = try makeInMemoryContainer()
        let context = container.viewContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let ts1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 8, minute: 0, second: 10))!
        let ts2 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13, hour: 8, minute: 0, second: 50))!

        context.performAndWait {
            let a = BodyMeasurement(context: context)
            a.id = UUID()
            a.timestamp = ts1
            a.weightKg = 70.0
            a.bodyFatPercent = 18.5
            a.deviceId = "device-1"

            let b = BodyMeasurement(context: context)
            b.id = UUID()
            b.timestamp = ts2
            b.weightKg = 70.0
            b.impedance = 500
            b.deviceId = "device-1"
        }

        try context.performAndWaitThrowing {
            var report = SyncReport()
            try CoreDataDeduplicator.reconcileAll(in: context, report: &report)
            try context.save()
        }

        let results = try context.fetch(NSFetchRequest<BodyMeasurement>(entityName: "BodyMeasurement"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].weightKg, 70.0, accuracy: 0.001)
        XCTAssertEqual(results[0].bodyFatPercent, 18.5, accuracy: 0.001)
        XCTAssertEqual(results[0].impedance, 500)
    }

    func testXiaomiAdvertisementParserParsesStableKgMeasurement() throws {
        let flags: UInt16 = (1 << 10) | (1 << 14)
        let year: UInt16 = 2026
        let impedance: UInt16 = 500
        let weightRaw: UInt16 = 14000

        let data = Data([
            UInt8(flags & 0xFF),
            UInt8((flags >> 8) & 0xFF),
            UInt8(year & 0xFF),
            UInt8((year >> 8) & 0xFF),
            2,
            13,
            8,
            0,
            0,
            UInt8(impedance & 0xFF),
            UInt8((impedance >> 8) & 0xFF),
            UInt8(weightRaw & 0xFF),
            UInt8((weightRaw >> 8) & 0xFF),
        ])

        let m = XiaomiScaleAdvertisementParser.parse(serviceData: data, deviceId: "device-1", deviceName: "S400")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.weightKg ?? 0, 70.0, accuracy: 0.001)
        XCTAssertEqual(m?.impedance ?? 0, 500)
        XCTAssertEqual(m?.deviceName, "S400")
        XCTAssertEqual(m?.source, "bluetooth_adv")
    }

    func testGattParsers() throws {
        let weightRaw: UInt16 = 14000
        let weightData = Data([0x00, UInt8(weightRaw & 0xFF), UInt8((weightRaw >> 8) & 0xFF)])
        let w = GattWeightMeasurementParser.parse(data: weightData)
        XCTAssertNotNil(w)
        XCTAssertEqual(w?.weightKg ?? 0, 70.0, accuracy: 0.001)

        let fatRaw: UInt16 = 185
        let fatData = Data([0x00, 0x00, UInt8(fatRaw & 0xFF), UInt8((fatRaw >> 8) & 0xFF)])
        let f = GattBodyCompositionParser.parse(data: fatData)
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.bodyFatPercent ?? 0, 18.5, accuracy: 0.001)
    }

    private func makeInMemoryContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MuscleMetric")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        return container
    }
}

extension NSManagedObjectContext {
    func performAndWaitThrowing(_ block: () throws -> Void) throws {
        var result: Result<Void, Error> = .success(())
        performAndWait {
            do {
                try block()
            } catch {
                result = .failure(error)
            }
        }
        try result.get()
    }
}
