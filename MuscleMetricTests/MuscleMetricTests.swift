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
