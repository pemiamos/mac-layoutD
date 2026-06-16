import Foundation

public struct LayoutTemplateLibrary: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var sourceProjectTitle: String?
    public var exportedAt: Date
    public var templates: [SavedLayoutTemplate]

    public init(
        formatVersion: Int = 1,
        sourceProjectTitle: String? = nil,
        exportedAt: Date = Date(),
        templates: [SavedLayoutTemplate]
    ) {
        self.formatVersion = formatVersion
        self.sourceProjectTitle = sourceProjectTitle
        self.exportedAt = exportedAt
        self.templates = templates
    }

    public init(project: BookProject, exportedAt: Date = Date()) {
        self.init(
            sourceProjectTitle: project.metadata.title,
            exportedAt: exportedAt,
            templates: project.safeSavedLayoutTemplates
        )
    }

    public static func encode(_ library: LayoutTemplateLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(library)
    }

    public static func decode(_ data: Data) throws -> LayoutTemplateLibrary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LayoutTemplateLibrary.self, from: data)
    }
}

public extension BookProject {
    mutating func importLayoutTemplateLibrary(_ library: LayoutTemplateLibrary) {
        var existing = safeSavedLayoutTemplates
        var usedNames = Set(existing.map(\.name))
        let existingIDs = Set(existing.map(\.id))

        for template in library.templates where !existingIDs.contains(template.id) {
            var imported = template
            imported.name = uniqueTemplateName(imported.name, usedNames: usedNames)
            usedNames.insert(imported.name)
            existing.append(imported)
        }

        safeSavedLayoutTemplates = existing
    }

    func importingLayoutTemplateLibrary(_ library: LayoutTemplateLibrary) -> BookProject {
        var copy = self
        copy.importLayoutTemplateLibrary(library)
        return copy
    }

    private func uniqueTemplateName(_ name: String, usedNames: Set<String>) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "未命名模板" : trimmed
        guard usedNames.contains(baseName) else {
            return baseName
        }

        var suffix = 2
        while usedNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }
}
