import Foundation
import CoreData

struct TagImportReport: Equatable {
    var inserted: Int = 0
    var merged: Int = 0
    var skipped: Int = 0
}

enum TagImportExportError: Error, LocalizedError {
    case invalidFormat
    case unsupportedSchema
    case unsupportedKind
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "文件格式不正确"
        case .unsupportedSchema: return "不支持的标签文件 schema"
        case .unsupportedKind: return "不支持的标签类型"
        case .unsupportedVersion: return "不支持的标签文件版本"
        }
    }
}

final class TagImportExportService {
    struct Meta: Codable, Equatable {
        var schema: String
        var kind: String
        var version: Int
        var exportedAt: Date
    }

    struct TrainingTagDTO: Codable, Hashable {
        var id: UUID
        var name: String
        var level: Int16
        var category: String?
        var parentId: UUID?
    }

    struct DietTagDTO: Codable, Hashable {
        var id: UUID
        var name: String
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
    }

    struct TrainingTagFile: Codable {
        var meta: Meta
        var tags: [TrainingTagDTO]
    }

    struct DietTagFile: Codable {
        var meta: Meta
        var tags: [DietTagDTO]
    }

    private struct MetaWrapper: Decodable {
        var meta: Meta
    }

    static let schema = "musclemetric.tags"
    static let trainingKind = "training"
    static let dietKind = "diet"
    static let currentVersion = 1

    static func exportTrainingTags(from context: NSManagedObjectContext, selectedIds: Set<UUID>?) async throws -> URL {
        try await context.performAsync {
            try normalizeTrainingTagIds(in: context)

            let request = NSFetchRequest<TrainingTag>(entityName: "TrainingTag")
            request.returnsObjectsAsFaults = false
            request.includesPropertyValues = true
            let allTags = try context.fetch(request)
            let allById: [UUID: TrainingTag] = Dictionary(uniqueKeysWithValues: allTags.compactMap { tag in
                guard let id = tag.id else { return nil }
                return (id, tag)
            })

            let includedIds: Set<UUID>
            if let selectedIds {
                includedIds = trainingTagSelectionClosure(selectedIds: selectedIds, allById: allById)
            } else {
                includedIds = Set(allById.keys)
            }

            let dtos: [TrainingTagDTO] = includedIds.compactMap { id in
                guard let tag = allById[id] else { return nil }
                let name = tag.name ?? ""
                return TrainingTagDTO(
                    id: id,
                    name: name,
                    level: tag.level,
                    category: (tag.category ?? "").isEmpty ? nil : tag.category,
                    parentId: tag.parent?.id
                )
            }
            .sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level < rhs.level }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            let file = TrainingTagFile(
                meta: Meta(schema: schema, kind: trainingKind, version: currentVersion, exportedAt: Date()),
                tags: dtos
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)

            let url = makeExportURL(prefix: "musclemetric-training-tags", date: file.meta.exportedAt)
            try data.write(to: url, options: [.atomic])
            return url
        }
    }

    static func exportDietTags(from context: NSManagedObjectContext, selectedIds: Set<UUID>?) async throws -> URL {
        try await context.performAsync {
            try normalizeDietTagIds(in: context)

            let request = NSFetchRequest<DietTag>(entityName: "DietTag")
            request.returnsObjectsAsFaults = false
            request.includesPropertyValues = true
            let allTags = try context.fetch(request)
            let included: [DietTag] = {
                guard let selectedIds else { return allTags }
                let selected = Set(selectedIds)
                return allTags.filter { tag in
                    guard let id = tag.id else { return false }
                    return selected.contains(id)
                }
            }()

            let dtos: [DietTagDTO] = included.compactMap { tag in
                guard let id = tag.id else { return nil }
                return DietTagDTO(
                    id: id,
                    name: tag.name ?? "",
                    calories: tag.calories,
                    protein: tag.protein,
                    fat: tag.fat,
                    carbs: tag.carbs
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            let file = DietTagFile(
                meta: Meta(schema: schema, kind: dietKind, version: currentVersion, exportedAt: Date()),
                tags: dtos
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)

            let url = makeExportURL(prefix: "musclemetric-diet-tags", date: file.meta.exportedAt)
            try data.write(to: url, options: [.atomic])
            return url
        }
    }

    static func importTags(from url: URL, into context: NSManagedObjectContext) async throws -> TagImportReport {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let meta = try? decoder.decode(MetaWrapper.self, from: data).meta else {
            throw TagImportExportError.invalidFormat
        }
        guard meta.schema == schema else {
            throw TagImportExportError.unsupportedSchema
        }
        guard meta.version == currentVersion else {
            throw TagImportExportError.unsupportedVersion
        }

        switch meta.kind {
        case trainingKind:
            let file = try decoder.decode(TrainingTagFile.self, from: data)
            return try await importTrainingTags(file.tags, into: context)
        case dietKind:
            let file = try decoder.decode(DietTagFile.self, from: data)
            return try await importDietTags(file.tags, into: context)
        default:
            throw TagImportExportError.unsupportedKind
        }
    }

    private static func importTrainingTags(_ dtos: [TrainingTagDTO], into context: NSManagedObjectContext) async throws -> TagImportReport {
        try await context.performAsync {
            var report = TagImportReport()
            try normalizeTrainingTagIds(in: context)

            let request = NSFetchRequest<TrainingTag>(entityName: "TrainingTag")
            request.returnsObjectsAsFaults = false
            request.includesPropertyValues = true
            let existing = try context.fetch(request)

            var existingById: [UUID: TrainingTag] = [:]
            existingById.reserveCapacity(existing.count)
            for tag in existing {
                if let id = tag.id {
                    existingById[id] = tag
                }
            }

            var existingByKey: [String: TrainingTag] = [:]
            existingByKey.reserveCapacity(existing.count)
            for tag in existing {
                let key = trainingSemanticKey(level: tag.level, parentId: tag.parent?.id, name: tag.name ?? "")
                existingByKey[key] = tag
            }

            let sortedDtos = dtos.sorted { lhs, rhs in
                if lhs.level != rhs.level { return lhs.level < rhs.level }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            var importedById: [UUID: TrainingTag] = [:]
            importedById.reserveCapacity(sortedDtos.count)

            for dto in sortedDtos {
                let trimmedName = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedName.isEmpty {
                    report.skipped += 1
                    continue
                }

                if let existing = existingById[dto.id] {
                    mergeTraining(tag: existing, dto: dto)
                    importedById[dto.id] = existing
                    report.merged += 1
                    continue
                }

                let key = trainingSemanticKey(level: dto.level, parentId: dto.parentId, name: trimmedName)
                if let existing = existingByKey[key] {
                    mergeTraining(tag: existing, dto: dto)
                    importedById[dto.id] = existing
                    report.merged += 1
                    continue
                }

                let tag = TrainingTag(context: context)
                tag.id = dto.id
                tag.level = dto.level
                tag.name = trimmedName
                tag.category = dto.category
                importedById[dto.id] = tag
                existingById[dto.id] = tag
                existingByKey[key] = tag
                report.inserted += 1
            }

            for dto in sortedDtos {
                guard let tag = importedById[dto.id] ?? existingById[dto.id] else { continue }
                guard tag.parent == nil else { continue }
                guard let parentId = dto.parentId else { continue }
                if let parent = importedById[parentId] ?? existingById[parentId] {
                    tag.parent = parent
                }
            }

            if context.hasChanges {
                try context.save()
            }
            return report
        }
    }

    private static func importDietTags(_ dtos: [DietTagDTO], into context: NSManagedObjectContext) async throws -> TagImportReport {
        try await context.performAsync {
            var report = TagImportReport()
            try normalizeDietTagIds(in: context)

            let request = NSFetchRequest<DietTag>(entityName: "DietTag")
            request.returnsObjectsAsFaults = false
            request.includesPropertyValues = true
            let existing = try context.fetch(request)

            var existingById: [UUID: DietTag] = [:]
            existingById.reserveCapacity(existing.count)
            for tag in existing {
                if let id = tag.id {
                    existingById[id] = tag
                }
            }

            var existingByKey: [String: DietTag] = [:]
            existingByKey.reserveCapacity(existing.count)
            for tag in existing {
                let key = dietSemanticKey(tag.name ?? "")
                existingByKey[key] = tag
            }

            for dto in dtos {
                let trimmedName = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedName.isEmpty {
                    report.skipped += 1
                    continue
                }

                if let existing = existingById[dto.id] {
                    mergeDiet(tag: existing, dto: dto, name: trimmedName)
                    report.merged += 1
                    continue
                }

                let key = dietSemanticKey(trimmedName)
                if let existing = existingByKey[key] {
                    mergeDiet(tag: existing, dto: dto, name: trimmedName)
                    report.merged += 1
                    continue
                }

                let tag = DietTag(context: context)
                tag.id = dto.id
                tag.name = trimmedName
                tag.calories = dto.calories
                tag.protein = dto.protein
                tag.fat = dto.fat
                tag.carbs = dto.carbs
                existingById[dto.id] = tag
                existingByKey[key] = tag
                report.inserted += 1
            }

            if context.hasChanges {
                try context.save()
            }
            return report
        }
    }

    private static func mergeTraining(tag: TrainingTag, dto: TrainingTagDTO) {
        let trimmedName = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !trimmedName.isEmpty {
            tag.name = trimmedName
        }
        if (tag.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let v = dto.category, !v.isEmpty {
            tag.category = v
        }
        if tag.level == 0, dto.level != 0 {
            tag.level = dto.level
        }
        if tag.id == nil {
            tag.id = dto.id
        }
    }

    private static func mergeDiet(tag: DietTag, dto: DietTagDTO, name: String) {
        if (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.isEmpty {
            tag.name = name
        }
        if tag.calories == 0, dto.calories > 0 { tag.calories = dto.calories }
        if tag.protein == 0, dto.protein > 0 { tag.protein = dto.protein }
        if tag.fat == 0, dto.fat > 0 { tag.fat = dto.fat }
        if tag.carbs == 0, dto.carbs > 0 { tag.carbs = dto.carbs }
        if tag.id == nil {
            tag.id = dto.id
        }
    }

    private static func normalizeTrainingTagIds(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<TrainingTag>(entityName: "TrainingTag")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true
        let tags = try context.fetch(request)
        for tag in tags where tag.id == nil {
            tag.id = UUID()
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private static func normalizeDietTagIds(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<DietTag>(entityName: "DietTag")
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true
        let tags = try context.fetch(request)
        for tag in tags where tag.id == nil {
            tag.id = UUID()
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private static func trainingTagSelectionClosure(selectedIds: Set<UUID>, allById: [UUID: TrainingTag]) -> Set<UUID> {
        var included: Set<UUID> = []

        var childrenByParentId: [UUID: [UUID]] = [:]
        for (id, tag) in allById {
            guard let parentId = tag.parent?.id else { continue }
            childrenByParentId[parentId, default: []].append(id)
        }

        func includeAncestors(of id: UUID) {
            var currentId: UUID? = id
            var visited: Set<UUID> = []
            while let cid = currentId, let tag = allById[cid], let parentId = tag.parent?.id {
                if visited.contains(parentId) { break }
                visited.insert(parentId)
                included.insert(parentId)
                currentId = parentId
            }
        }

        func includeDescendants(of id: UUID) {
            var stack: [UUID] = [id]
            var visited: Set<UUID> = []
            while let current = stack.popLast() {
                if visited.contains(current) { continue }
                visited.insert(current)
                guard let children = childrenByParentId[current] else { continue }
                for child in children {
                    included.insert(child)
                    stack.append(child)
                }
            }
        }

        for id in selectedIds where allById[id] != nil {
            included.insert(id)
            includeAncestors(of: id)
            includeDescendants(of: id)
        }
        return included
    }

    private static func trainingSemanticKey(level: Int16, parentId: UUID?, name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if level <= 1 {
            return "\(level)|\(n)"
        }
        let pid = parentId?.uuidString ?? ""
        return "\(level)|\(pid)|\(n)"
    }

    private static func dietSemanticKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func makeExportURL(prefix: String, date: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let filename = "\(prefix)-\(stamp).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

